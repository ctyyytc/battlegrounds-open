extends RefCounted
# The source bundle is never deleted. Only this application's managed copy is removed.
const ROOT="user://resource_packs"
const PACKS=ROOT+"/packages"
const SELECTION=ROOT+"/selection.json"

static func selection() -> Dictionary:
	if not FileAccess.file_exists(SELECTION):return {}
	var value=JSON.parse_string(FileAccess.get_file_as_string(SELECTION))
	return value if value is Dictionary else {"mode":"invalid"}

static func valid_id(id: String) -> bool:
	var rx=RegEx.new();rx.compile("^[0-9a-f]{64}$");return rx.search(id)!=null

static func active_path(fallback: String="") -> String:
	var chosen=selection()
	if chosen.is_empty():return fallback
	if chosen.get("mode","")!="installed" or not valid_id(str(chosen.get("id",""))):return ""
	var path=PACKS.path_join(str(chosen.id)).path_join("pack.json")
	return path if FileAccess.file_exists(path) else ""

static func summary(fallback: String="") -> String:
	var chosen=selection()
	if chosen.is_empty():return "工程本地资源包" if FileAccess.file_exists(fallback) else "默认内容（未安装资源包）"
	if chosen.get("mode","")=="installed" and not active_path().is_empty():return str(chosen.get("name","本地资源包"))
	return "默认内容（未安装资源包）"

static func safe_relative(value: String) -> bool:
	return not value.is_empty() and not value.is_absolute_path() and ":" not in value and ".." not in value.replace("\\","/").split("/")

static func linked_component(base: String,relative: String) -> bool:
	var current=base
	for part in relative.replace("\\","/").split("/",false):
		var access=DirAccess.open(current)
		if access==null or access.is_link(part):return true
		current=current.path_join(part)
	return false

static func write_selection(value: Dictionary) -> int:
	var err=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	if err!=OK:return err
	var temporary=SELECTION+".tmp";var backup=SELECTION+".previous"
	var f=FileAccess.open(temporary,FileAccess.WRITE)
	if f==null:return FileAccess.get_open_error()
	f.store_string(JSON.stringify(value));f.flush();var stored_error=f.get_error();f.close()
	if stored_error!=OK:return stored_error
	var had_previous=FileAccess.file_exists(SELECTION)
	if had_previous:
		err=DirAccess.rename_absolute(ProjectSettings.globalize_path(SELECTION),ProjectSettings.globalize_path(backup))
		if err!=OK:return err
	err=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(SELECTION))
	if err!=OK and had_previous:DirAccess.rename_absolute(ProjectSettings.globalize_path(backup),ProjectSettings.globalize_path(SELECTION))
	elif had_previous:DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	return err

static func cleanup(id: String) -> Array:
	var warnings=[]
	if not valid_id(id):return warnings
	var base=PACKS.path_join(id)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)):return warnings
	if linked_component(ROOT,"packages/"+id+"/installed.json"):return ["安装副本的路径已变动，已停用并保留文件。"]
	var manifest=JSON.parse_string(FileAccess.get_file_as_string(base.path_join("installed.json")))
	if not manifest is Dictionary or manifest.get("id","")!=id or not manifest.get("files",null) is Array:return ["安装副本清单不可读，已停用并保留文件。"]
	var files=manifest.files.duplicate();files.append("installed.json");var folders=[]
	for relative in files:
		if not relative is String or not safe_relative(relative) or linked_component(base,relative):
			warnings.append("安装副本含变动路径，已跳过清理。");continue
		var path=base.path_join(relative)
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path))!=OK:warnings.append("部分安装文件暂时无法删除。")
		var parent=relative.get_base_dir()
		while parent!="" and parent!=".":
			if parent not in folders:folders.append(parent)
			parent=parent.get_base_dir()
	folders.sort_custom(func(a,b):return a.length()>b.length())
	for parent in folders:DirAccess.remove_absolute(ProjectSettings.globalize_path(base.path_join(parent)))
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(base))!=OK:warnings.append("已停用资源包，目录内的其它文件予以保留。")
	return warnings

static func install(source: String,inspection: Dictionary) -> Dictionary:
	if not inspection.get("ok",false) or inspection.get("path","")!=source:return {"ok":false,"error":"INVALID_PACK","diagnostics":inspection.get("diagnostics",[])}
	var data: Dictionary=inspection.data.duplicate(true)
	if int(data.schema_version)==1:
		for section in ["templates","ui","terms"]:data.erase(section)
	var id=(JSON.stringify(data)+str(Time.get_ticks_usec())+str(OS.get_process_id())).sha256_text()
	var base=PACKS.path_join(id);var files=["pack.json"];var sources={};var source_folder=source.get_base_dir()
	for relative in data.get("assets",{}).values():
		if relative==null:continue
		if not relative is String or not safe_relative(relative) or linked_component(source_folder,relative):return {"ok":false,"error":"INVALID_IMAGE_PATH"}
		if relative not in files:files.append(relative);sources[relative]=source_folder.path_join(relative)
	var err=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	if err!=OK:return {"ok":false,"error":"CREATE_DIRECTORY_FAILED"}
	var manifest={"id":id,"files":files}
	var f=FileAccess.open(base.path_join("installed.json"),FileAccess.WRITE)
	if f==null:return {"ok":false,"error":"WRITE_MANIFEST_FAILED"}
	f.store_string(JSON.stringify(manifest));f.close()
	for relative in sources:
		var destination=base.path_join(relative)
		err=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
		if err==OK:err=DirAccess.copy_absolute(ProjectSettings.globalize_path(sources[relative]),ProjectSettings.globalize_path(destination))
		if err!=OK or FileAccess.get_sha256(sources[relative])!=FileAccess.get_sha256(destination):
			cleanup(id);return {"ok":false,"error":"COPY_IMAGE_FAILED","path":relative}
	f=FileAccess.open(base.path_join("pack.json"),FileAccess.WRITE)
	if f==null:cleanup(id);return {"ok":false,"error":"WRITE_PACK_FAILED"}
	f.store_string(JSON.stringify(data));f.flush();err=f.get_error();f.close()
	if err!=OK:cleanup(id);return {"ok":false,"error":"WRITE_PACK_FAILED"}
	var previous=selection()
	err=write_selection({"version":1,"mode":"installed","id":id,"name":source_folder.get_file(),"source":source})
	if err!=OK:cleanup(id);return {"ok":false,"error":"ACTIVATE_PACK_FAILED"}
	var warnings=cleanup(str(previous.get("id","")))
	return {"ok":true,"id":id,"path":base.path_join("pack.json"),"images":sources.size(),"warnings":warnings}

static func uninstall() -> Dictionary:
	var previous=selection();var err=write_selection({"version":1,"mode":"default"})
	if err!=OK:return {"ok":false,"error":"DEACTIVATE_PACK_FAILED"}
	return {"ok":true,"warnings":cleanup(str(previous.get("id",""))),"source_bundle_preserved":true}
