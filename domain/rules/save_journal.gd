extends RefCounted

static func hash_bytes(bytes: PackedByteArray) -> PackedByteArray:
 var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(bytes);return digest.finish()
static func prepare(engine,path: String) -> Dictionary:
 var prior=engine.persistence_cache.get(path,{})
 if prior.get("epoch",-1)!=engine.persistence_epoch:
  prior={"epoch":engine.persistence_epoch,"path":path+".history."+str(Time.get_unix_time_from_system())+"."+str(Time.get_ticks_usec()),"offset":0,"events":0,"commands":0,"receipt_keys":{},"chain":""}
 var next=prior.duplicate(true);var receipts={}
 for key in engine.receipts:
  if not next.receipt_keys.has(key):receipts[key]=engine.receipts[key];next.receipt_keys[key]=true
 var events=engine.events.slice(int(prior.events));var commands=engine.command_log.slice(int(prior.commands))
 if not events.is_empty() or not receipts.is_empty() or not commands.is_empty() or int(prior.offset)==0:
  var raw=var_to_bytes({"events":events,"receipts":receipts,"command_log":commands})
  var payload=PackedByteArray();payload.resize(8);payload.encode_u64(0,raw.size());payload.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
  var digest=hash_bytes(payload);var header=PackedByteArray();header.resize(8);header.encode_u64(0,payload.size());var chunk=header+digest+payload
  var file=FileAccess.open(str(prior.path),FileAccess.READ_WRITE if FileAccess.file_exists(str(prior.path)) else FileAccess.WRITE_READ)
  if file==null:return {"error":FileAccess.get_open_error()}
  file.seek(int(prior.offset));file.store_buffer(chunk);file.flush();file.seek(int(prior.offset));var verified=file.get_buffer(chunk.size());file.close()
  if verified!=chunk:return {"error":ERR_FILE_CORRUPT}
  next.offset=int(prior.offset)+chunk.size();next.chain=(str(prior.chain)+digest.hex_encode()).sha256_text()
 next.events=engine.events.size();next.commands=engine.command_log.size()
 return {"error":OK,"cache":next,"body":{"state":engine.state,"spell_history":engine.spell_history,"journal":{"path":next.path,"offset":next.offset,"events":next.events,"commands":next.commands,"receipts":next.receipt_keys.size(),"chain":next.chain}}}
static func read(path: String,data: Dictionary) -> Dictionary:
 var meta=data.journal
 if not str(meta.get("path","")).begins_with(path.trim_suffix(".bak")+".history."):return {"error":"INVALID_HISTORY_PATH"}
 var file=FileAccess.open(str(meta.path),FileAccess.READ)
 if file==null:return {"error":"HISTORY_NOT_FOUND"}
 var events=[];var commands=[];var receipts={};var chain="";var offset=int(meta.get("offset",-1))
 if offset<0 or offset>file.get_length():file.close();return {"error":"HISTORY_TRUNCATED"}
 while file.get_position()<offset:
  if offset-file.get_position()<40:file.close();return {"error":"HISTORY_TRUNCATED"}
  var size=int(file.get_64());var digest=file.get_buffer(32)
  if size<8 or size>offset-file.get_position():file.close();return {"error":"HISTORY_TRUNCATED"}
  var payload=file.get_buffer(size)
  if hash_bytes(payload)!=digest:file.close();return {"error":"HISTORY_CHECKSUM_MISMATCH"}
  var unpacked=bytes_to_var(payload.slice(8).decompress(int(payload.decode_u64(0)),FileAccess.COMPRESSION_ZSTD))
  if not unpacked is Dictionary:file.close();return {"error":"INVALID_HISTORY"}
  events.append_array(unpacked.events);commands.append_array(unpacked.command_log);receipts.merge(unpacked.receipts)
  chain=(chain+digest.hex_encode()).sha256_text()
 file.close()
 if chain!=meta.chain or events.size()!=int(meta.events) or commands.size()!=int(meta.commands) or receipts.size()!=int(meta.receipts):return {"error":"HISTORY_CHECKSUM_MISMATCH"}
 var complete={"state":data.state,"spell_history":data.get("spell_history",[]),"events":events,"command_log":commands,"receipts":receipts}
 var keys={}
 for key in receipts:keys[key]=true
 return {"error":"","data":complete,"cache":{"path":meta.path,"offset":offset,"events":events.size(),"commands":commands.size(),"receipt_keys":keys,"chain":chain}}
