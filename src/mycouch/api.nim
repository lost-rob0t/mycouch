import
  httpclient, uri,
  json, tables, strformat, strutils
import ./private/utils

type
  CouchDBClient* = object
    hc*: HttpClient
    baseUrl*: string

  FeedVariants* = enum
    FVNormal = "normal"
    FVLongPoll = "longpoll"
    FVContinuous = "continuous"
    FVEventSource = "eventsource"

  BatchVariants* = enum
    BVNon = ""
    BVOk = "ok"

  UpdateVariants* = enum
    UVTrue = "true"
    UVFalse = "false"
    UVLazy = "lazy"

using
  self: CouchDBClient
  db: string
  docid: string
  ddoc: string
  attname: string
  view: string
  node: string
  section: string


proc changeHeaders(lastHeaders: HttpHeaders, changedData: openArray[tuple[k: string, v: string]]): HttpHeaders =
  result.deepcopy lastHeaders

  for (k, v) in changedData:
    result.add v, k

# INITIATE -----------------------------------------------

proc newCouchDBClient*(host: string = "http://localhost", port = 5984): CouchDBClient =
  var client = newHttpClient()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})

  CouchDBClient(hc: client, baseUrl: fmt"{host}:{port}")

# SERVER API ----------------------------------------------------------------------

proc serverInfo*(self): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/server/common.html#api-server-root
  let req = self.hc.get(fmt"{self.baseUrl}/")

  doAssert req.code == Http200
  return req.body.parseJson

proc activeTasks*(self): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#active-tasks
  let req = self.hc.get(fmt"{self.baseUrl}/_active_tasks/")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc allDBs*(self; descending = false, limit, skip = 0, startkey, endKey = newJObject()): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#all-dbs

  var queryParams = @[
    ("descending", $descending),
    ("skip", $skip),
  ].createNadd([
    limit,
    startKey,
    endKey,
  ], allDBsDefaults)

  let req = self.hc.get(fmt"{self.baseUrl}/_all_dbs/?" & encodeQuery(queryParams))

  doAssert req.code == Http200
  return req.body.parseJson

proc DBsInfo*(self; keys: openArray[string]): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#dbs-info

  let req = self.hc.post(fmt"{self.baseUrl}/_dbs_info", $ %*{"keys": keys})

  doAssert req.code == Http200 # or bad request 400
  return req.body.parseJson

# TODO (cluster setup) https://docs.couchdb.org/en/latest/api/server/common.html#cluster-setup

proc DBupdates*(self; feed: string, timeout = 60, heartbeat = 60000, since = ""): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#db-updates
  let queryParams = @[
    ("feed", feed),
    ("since", since),
    ("timeout", $timeout),
    ("heartbeat", $heartbeat),
  ]
  let req = self.hc.get(fmt"{self.baseUrl}/_db_updates/?" & encodeQuery(queryParams))

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc membership*(self): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#membership
  let req = self.hc.get(fmt"{self.baseUrl}/_membership")

  doAssert req.code == Http200
  return req.body.parseJson

proc replicate*(self;
  source, target: string,
  cancel, continuous, create_target = false,
  create_target_params: JsonNode = newJObject(),
  doc_ids = newseq[string](),
  filter: string = "",
  source_proxy, target_proxy: string = ""
): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#replicate

  var body = ( %* {
    "source": source,
    "target": target,
  }).createNadd([
    cancel,
    continuous,
    create_target,
    doc_ids,
    filter,
    source_proxy, target_proxy,
  ], replicateDefaults)

  let req = self.hc.post(fmt"{self.baseUrl}/_replicate", $body)

  doAssert req.code in {Http200, Http202}
  return req.body.parseJson

proc schedulerJobs*(self; limit, skip = 0): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#scheduler-jobs

  var queryParams = newseq[DoubleStrTuple]().createNadd([
    limit,
    skip
  ], schedulerJobsDefaults)

  let req = self.hc.get(fmt"{self.baseUrl}/_all_dbs/?" & encodeQuery(queryParams))

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc schedulerDocs*(self; replicatorDB, doc_id = "", limit, skip = 0, ): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#scheduler-docs
  ## https://docs.couchdb.org/en/latest/api/server/common.html#get--_scheduler-docs-replicator_db
  let url =
    fmt"{self.baseUrl}/_scheduler/docs" &
    (
      if replicatorDB != "": fmt"/{replicatorDB}"
      else:
        var queryParams = newseq[DoubleStrTuple]().createNadd([limit, skip], schedulerJobsDefaults)
        "?" & encodeQuery(queryParams)
    )

  let req = self.hc.get(url)

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc schedulerDoc*(self, docid; replicatorDB: string): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#get--_scheduler-docs-replicator_db-docid
  let req = self.hc.get(fmt"{self.baseUrl}/_scheduler/docs/{replicatorDB}/{docid}")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc nodeInfo*(self, node): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#node-node-name
  let req = self.hc.get(fmt"{self.baseUrl}/_node/{node}")

  doAssert req.code == Http200
  return req.body.parseJson

proc nodeStats*(self, node): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#node-node-name
  let req = self.hc.get(fmt"{self.baseUrl}/_node/{node}/_stats")

  doAssert req.code == Http200
  return req.body.parseJson

proc nodeSystem*(self, node): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#node-node-name
  let req = self.hc.get(fmt"{self.baseUrl}/_node/{node}/_system")

  doAssert req.code == Http200
  return req.body.parseJson

proc nodeRestart*(self, node): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#node-node-name-restart
  let req = self.hc.post(fmt"{self.baseUrl}/_node/{node}/_restart")

  doAssert req.code == Http200
  return req.body.parseJson

## maybeTODO: https://docs.couchdb.org/en/latest/api/server/common.html#search-analyze

proc up*(self, node): bool =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#up
  self.hc.get(fmt"{self.baseUrl}/_up").code == Http200 # or 404

proc uuids*(self; count = 1): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#uuids
  let req = self.hc.get(fmt"{self.baseUrl}/_uuids?count={count}")

  doAssert req.code == Http200 # or 400
  return req.body.parseJson

proc reshard*(self): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#reshard
  let req = self.hc.get(fmt"{self.baseUrl}/_reshard")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc reshardState*(self): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#get--_reshard-state
  let req = self.hc.get(fmt"{self.baseUrl}/_reshard/state")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

type ReshardStates* = enum
  stopped = "stopped"
  running = "running"
proc changeReshardState*(self; state: string, state_reason = "") {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#put--_reshard-state

  var body = (%*{"state": state}).createNadd([state_reason], changeReshardStateDefaults)

  let req = self.hc.put(fmt"{self.baseUrl}/_reshard/state", $ body)
  doAssert req.code == Http200 # 400 or 401

proc reshardJobs*(self; jobId = ""): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#get--_reshard-jobs
  ## https://docs.couchdb.org/en/latest/api/server/common.html#get--_reshard-jobs-jobid
  let req = self.hc.get(fmt"{self.baseUrl}/_reshard/jobs/" & jobId)

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc createReshadJob*(self, db; `type`, node, `range`, shard, error = "") {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#post--_reshard-jobs
  var body = ( %* {
    "type": `type`,
    "db": db,
  }).createNadd([
    node, `range`, shard, error
  ], createReshadJobDefaults)

  let req = self.hc.post(fmt"{self.baseUrl}/_reshard/jobs", $ body)
  doAssert req.code == Http200 # or bad request 400

proc deleteReshadJob*(self; jobId: string) =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#delete--_reshard-jobs-jobid
  let req = self.hc.post(fmt"{self.baseUrl}/_reshard/jobs/{jobid}")
  doAssert req.code == Http200 # or bad request 400

proc reshadJobState*(self; jobId: string): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#get--_reshard-jobs-jobid-state
  let req = self.hc.get(fmt"{self.baseUrl}/_reshard/jobs/{jobId}/state")
  doAssert req.code == Http200 # or 401, 404

  req.body.parseJson

proc changeReshardJobState*(self; jobId, state: string, state_reason = "") {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/server/common.html#put--_reshard-state

  var body = ( %* {"state": state}).createNadd([state_reason], changeReshardStateDefaults)

  let req = self.hc.put(fmt"{self.baseUrl}/_reshard/jobs/{jobId}/state", $ body)
  doAssert req.code == Http200 # 400 or 401

proc getCurrentSession*(self): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/server/authn.html#get--_session
  let req = self.hc.get(fmt"{self.baseUrl}/_session")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc cookieAuthenticate*(self; username, password: string): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/server/authn.html#post--_session
  let req = self.hc.post(fmt"{self.baseUrl}/_session", $ %* {
    "name": username,
    "password": password
  })

  doAssert req.code == Http200 # or 401
  self.hc.headers.add "Cookie", req.headers["Set-Cookie"]

  return req.body.parseJson

proc deleteCookieSession*(self) =
  ## https://docs.couchdb.org/en/stable/api/server/authn.html#delete--_session
  let req = self.hc.delete(fmt"{self.baseUrl}/_session")

  doAssert req.code == Http200

# TODO proxy-auth, jwf-auth

proc getNodeConfig*(self, node): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/server/configuration.html#get--_node-node-name-_config
  let req = self.hc.get(fmt"{self.baseUrl}/_node/{node}/_config")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc getNodeSetionConfig*(self, node, section; ): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/server/configuration.html#node-node-name-config-section
  let req = self.hc.get(fmt"{self.baseUrl}/_node/{node}/_config/{section}")

  doAssert req.code == Http200 # or 401
  return req.body.parseJson

proc getNodeSetionKeyConfig*(self, node, section; key: string): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/server/configuration.html#get--_node-node-name-_config-section-key
  let req = self.hc.get(fmt"{self.baseUrl}/_node/{node}/_config/{section}/{key}")

  doAssert req.code == Http200 # or 401

proc updateNodeSetionKeyConfig*(self, node, section; key: string, newval: auto) =
  ## https://docs.couchdb.org/en/stable/api/server/configuration.html#get--_node-node-name-_config-section-key
  let req = self.hc.put(fmt"{self.baseUrl}/_node/{node}/_config/{section}/{key}", $ % newval)
  doAssert req.code == Http200 # or 401

proc deleteNodeSetionKeyConfig*(self, node, section; key: string) =
  ## https://docs.couchdb.org/en/stable/api/server/configuration.html#get--_node-node-name-_config-section-key
  let req = self.hc.delete(fmt"{self.baseUrl}/_node/{node}/_config/{section}/{key}")
  doAssert req.code == Http200 # or 401

proc reloadConfigs*(self, node) =
  ## https://docs.couchdb.org/en/stable/api/server/configuration.html#get--_node-node-name-_config-section-key
  let req = self.hc.post(fmt"{self.baseUrl}/_node/{node}/_config/_reload")
  doAssert req.code == Http200 # or 401

# DATEBASE API ------------------------------------------------------------

proc isDBexists*(self, db): bool =
  ## https://docs.couchdb.org/en/latest/api/database/common.html#head--db
  let req = self.hc.head(fmt"{self.baseUrl}/{db}")
  req.code == Http200

proc getDBinfo*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/common.html#get--db
  let req = self.hc.get(fmt"{self.baseUrl}/{db}")

  doAssert req.code == Http200
  req.body.parseJson

proc createDB*(self, db; q, n = -1, partioned = false): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/common.html#put--db
  var body = createNadd(%*{}, [q, n, partioned], createDBDefaults)

  let req = self.hc.put(fmt"{self.baseUrl}/{db}")

  doAssert req.code in {Http201, Http202}
  req.body.parseJson

proc deleteDB*(self, db) =
  ## https://docs.couchdb.org/en/latest/api/database/common.html#delete--db
  let req = self.hc.delete(fmt"{self.baseUrl}/{db}")

  doAssert req.code in {Http200, Http202}

proc createDoc*(self, db; doc: JsonNode, batch = BVNon): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/common.html#post--db
  var queryParams = newseq[DoubleStrTuple]().createNadd([batch], createDocDefaults)
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/?" & encodeQuery(queryParams), $doc)

  doAssert req.code in {Http201, Http202}
  req.body.parseJson

proc allDocs*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/bulk-api.html#db-all-docs
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_all_docs/")

  doAssert req.code == Http200
  req.body.parseJson

proc allDocs*(self, db; keys: seq[string]): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/bulk-api.html#post--db-_all_docs
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_all_docs/", $ %*{"keys": keys})

  doAssert req.code == Http200
  req.body.parseJson

proc designDocs*(self, db;
  conflicts, descending = false,
  startkey, endkey = "",
  startkey_docid, endkey_docid = "",
  include_docs = false,
  inclusive_end = true,
  key = "",
  keys = newseq[string](),
  limit, skip = 0,
  update_seq = false,
): JsonNode {.captureDefaults.} =
  var queryParams = newseq[DoubleStrTuple]().createNadd([
    conflicts, descending,
    startkey, endkey,
    startkey_docid, endkey_docid,
    include_docs,
    inclusive_end,
    key,
    limit, skip,
    update_seq,
  ], designDocsDefaults)
  ## https://docs.couchdb.org/en/latest/api/database/bulk-api.html#db-design-docs

  let
    url = fmt"{self.baseUrl}/{db}/_design_docs/?" & encodeQuery(queryParams)
    req =
      if keys == designDocsDefaults.keys:
        self.hc.get(url)
      else:
        self.hc.post(url, $ %*{"keys": keys})

  doAssert req.code == Http200
  req.body.parseJson

proc allDocs*(self, db; queries: JsonNode): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/bulk-api.html#post--db-_all_docs-queries
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_all_docs/queries", $queries)

  doAssert req.code == Http200
  req.body.parseJson

proc bulkGet*(self, db; docs: JsonNode, revs = false): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/bulk-api.html#db-bulk-get
  var queryParams = newseq[DoubleStrTuple]().createNadd([revs], bulkGetDefaults)
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_bulk_get?" & encodeQuery(queryParams), $docs)

  doAssert req.code == Http200
  req.body.parseJson

proc bulkDocs*(self, db; docs: JsonNode, new_edits = true): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/bulk-api.html#db-bulk-docs
  var body = ( %* {"docs": docs}).createNadd([new_edits], bulkDocsDefaults)
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_bulk_docs", $body)

  doAssert req.code == Http201
  req.body.parseJson

proc find*(self, db;
  selector: JsonNode,
  limit = 0,
  skip = 0,
  sort = newJObject(),
  fields = newseq[string](),
  use_index = "",
  use_indexes = newseq[string](),
  conflicts = false,
  r = 1,
  bookmark = "",
  update = true,
  stable = false,
  execution_stats = false
): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/find.html#db-find
  var body = (%{"selector": selector}).createNadd([
    limit,
    skip,
    sort,
    fields,
    conflicts,
    r,
    bookmark,
    update,
    stable,
    execution_stats,
  ], findDefaults)

  if use_index != "":
    body["use_index"] = % use_index
  elif use_indexes.len != 0:
    body["use_index"] = % use_indexes

  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_find", $body)

  doAssert req.code == Http200
  req.body.parseJson

proc createIndex*(self, db;
  index: JsonNode,
  ddoc,
  name,
  `type` = "",
  partitioned = false
): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/find.html#db-index
  var body = createNadd( %* {}, [
    ddoc,
    name,
    `type`,
    partitioned
  ], createIndexDefaults)

  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_index", $body)

  doAssert req.code == Http200
  req.body.parseJson

proc getIndexes*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/find.html#get--db-_index
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_index")

  doAssert req.code == Http200
  req.body.parseJson

proc deleteIndex*(self, db, ddoc; name: string) =
  ## https://docs.couchdb.org/en/latest/api/database/find.html#delete--db-_index,ddoc;json-name
  let req = self.hc.delete(fmt"{self.baseUrl}/{db}/_index/{ddoc}/json/{name}")
  doAssert req.code == Http200

proc explain*(self, db): JsonNode =
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_explain")

  doAssert req.code == Http200
  req.body.parseJson

proc shards*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/shard.html
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_shards")

  doAssert req.code == Http200
  req.body.parseJson

proc shardsDoc*(self, db, docId): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/shard.html#db-shards-doc
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_shards/{docid}")

  doAssert req.code == Http200
  req.body.parseJson

proc syncShards*(self, db, docId): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/shard.html#db-sync-shards
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_sync_shards")

  doAssert req.code == Http200
  req.body.parseJson

proc changes*(self, db;
    handleChanges: proc(data: JsonNode),
    doc_ids = newseq[string](),
    conflicts,
    descending = false,
    feed,
    filter = "",
    heartbeat = 60000,
    include_docs,
    attachments,
    att_encoding_info = false,
    `last-event-id` = 0,
    limit = 1,
    since = 0,
    style: string,
    timeout = 60000,
    view = "",
    seq_interval = 0,
): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/database/shard.html#db-sync-shards
  var queryParams = newseq[DoubleStrTuple]().createNadd([
    conflicts,
    descending,
    feed,
    filter,
    heartbeat,
    include_docs,
    attachments,
    att_encoding_info,
    `last-event-id`,
    limit,
    since,
    timeout,
    view,
    seq_interval,
  ], changesDefaults)

  let url = fmt"{self.baseUrl}/{db}/_changes?" & encodeQuery(queryParams)
  let req =
    if docids.len != 0:
      self.hc.post(url, $ %* {"doc_ids": docids})
    else:
      self.hc.get(url)

  # FIXME
  doAssert req.code == Http200
  req.body.parseJson

proc compact*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/compact.html#db-compact
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_compact")

  doAssert req.code == Http202
  req.body.parseJson

proc compactDesignDoc*(self, db, ddoc): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/compact.html#db-compact-design-doc
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_compact/{ddoc}")

  doAssert req.code == Http202
  req.body.parseJson

proc viewCleanup*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/compact.html#db-view-cleanup
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_view_cleanup")

  doAssert req.code == Http202
  req.body.parseJson

proc getSecurity*(self, db): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/security.html#get--db-_security
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_security")

  doAssert req.code == Http200
  req.body.parseJson

proc setSecurity*(self, db; admins, members: JsonNode): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/security.html#put--db-_security
  let req = self.hc.put(fmt"{self.baseUrl}/{db}/_security", $ %* {
    "admins": admins,
    "members": members,
  })

  doAssert req.code == Http200
  req.body.parseJson

proc purge*(self, db; obj: JsonNode): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/misc.html#db-purge
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_security", $ obj)

  doAssert req.code == Http200
  req.body.parseJson

proc getPurgedInfosLimit*(self, db): int =
  ## https://docs.couchdb.org/en/latest/api/database/misc.html#get--db-_purged_infos_limit
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_purged_infos_limit")

  doAssert req.code == Http200
  req.body.parseInt

proc setPurgedInfosLimit*(self, db; limit: int) =
  ## https://docs.couchdb.org/en/latest/api/database/misc.html#put--db-_purged_infos_limit
  let req = self.hc.put(fmt"{self.baseUrl}/{db}/_purged_infos_limit", $limit)

  doAssert req.code == Http200

proc revsDiff*(self, db; obj: JsonNode): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/database/misc.html#db-missing-revs
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_revs_diff", $ obj)

  doAssert req.code == Http200
  req.body.parseJson

proc getRevsLimit*(self, db): int =
  ## https://docs.couchdb.org/en/latest/api/database/misc.html#get--db-_revs_limit
  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_revs_limit")

  doAssert req.code == Http200
  req.body.parseInt

proc setRevsLimit*(self, db; limit: int) =
  ## https://docs.couchdb.org/en/latest/api/database/misc.html#put--db-_revs_limit
  let req = self.hc.put(fmt"{self.baseUrl}/{db}/_revs_limit", $limit)

  doAssert req.code == Http200

# DOCUMENTs API ------------------------------------------------------------

proc getDoc*(self, db, docid; headOnly: static[bool] = false,
  attachments,
  att_encoding_info = false,
  atts_since = newseq[string](),
  conflicts,
  deleted_conflicts = false,
  latest,
  local_seq,
  meta = false,
  open_revs = newseq[string](),
  all = false,
  rev = "",
  revs,
  revs_info = false
): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/document/common.html#get--db-docid
  ## https://docs.couchdb.org/en/latest/api/document/common.html#head--db-docid
  var queryParams = newseq[DoubleStrTuple]().createNadd([
    attachments,
    att_encoding_info,
    atts_since,
    conflicts,
    deleted_conflicts,
    latest,
    local_seq,
    meta,
    open_revs,
    rev,
    revs,
    revs_info,
  ], getDocDefaults)

  if all:
    queryParams.add ("open_revs", "all")

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/{docid}?" & encodeQuery(queryParams),
    httpMethod =
    if headOnly: HttpHead
      else: HttpGet
    )

  doAssert req.code.int < 400, $req.code
  req.body.parseJson

proc createOrUpdateDoc*(self, db, docid; obj: JsonNode): JsonNode =
  ## https://docs.couchdb.org/en/latest/api/document/common.html#put--db-docid
  let req = self.hc.put(fmt"{self.baseUrl}/{db}/{docid}", $obj)

  doAssert req.code in {Http201, Http202}
  req.body.parseJson

proc deleteDoc*(self, db, docid; rev: string, batch = BVNon, new_edits = false) {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/document/common.html#delete--db-docid
  var queryParams = newseq[DoubleStrTuple]().createNadd([batch, new_edits], deleteDocDefaults)
  let req = self.hc.delete(fmt"{self.baseUrl}/{db}/{docid}?" & encodeQuery(queryParams))

  doAssert req.code in {Http200, Http202}

proc copyDoc*(self, db, docid; destination: string, rev = "", batch = BVNon): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/document/common.html#copy--db-docid
  var queryParams = newseq[DoubleStrTuple]().createNadd([rev, batch], copyDocDefaults)

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/{docid}?" & encodeQuery(queryParams),
    httpMethod = "COPY",
    headers = changeHeaders(self.hc.headers, [("Destination", destination)])
  )

  doAssert req.code in {Http201, Http202}
  req.body.parseJson

proc getDocAtt*(self, db, docid, attname; headOnly: static[bool] = false, rev = ""): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/document/attachments.html#head--db-docid-attname
  ## https://docs.couchdb.org/en/latest/api/document/attachments.html#get--db-docid-attname
  var queryParams = newseq[DoubleStrTuple].createNadd([rev], getDocDefaults)

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/{docid}/{attname}?" & encodeQuery(queryParams),
    httpMethod =
    if headOnly: HttpHead
      else: HttpGet
    )

  doAssert req.code == Http200
  req.body.parseJson

proc uploadDocAtt*(self, db, docid, attname; contentType, content: string, rev = ""): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/document/attachments.html#put--db-docid-attname
  var queryParams = newseq[DoubleStrTuple]().createNadd([rev], getDocDefaults)

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/{docid}/{attname}?" & encodeQuery(queryParams),
    httpMethod = HttpPut,
    headers = changeHeaders(self.hc.headers, [
      ("Content-Type", content),
      ("Content-Length", $content.len)
    ])
  )

  doAssert req.code in {Http201, Http202}
  req.body.parseJson

proc deleteDocAtt*(self, db, docid; rev: string, batch = BVNon) {.captureDefaults.} =
  ## https://docs.couchdb.org/en/latest/api/document/attachments.html#delete--db-docid-attname

  var queryParams = @[("rev", rev)].createNadd([batch], deleteDocDefaults)
  let req = self.hc.delete(fmt"{self.baseUrl}/{db}/{docid}?" & encodeQuery(queryParams))

  doAssert req.code in {Http200, Http202}

# DESIGN DOCUMENTs API ------------------------------------------------------------

proc getDesignDoc*(self, db, ddoc; headOnly: static[bool] = false): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#head--db-_design-ddoc

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/_design/{ddoc}",
    httpMethod =
    if headOnly: HttpHead
      else: HttpGet
  )

  doAssert req.code == Http200
  req.body.parseJson

proc createOrUpdateDesignDoc*(self, db;
  ddoc: string,
  language: string,
  options: JsonNode,
  filters: seq[string],
  updates: JsonNode,
  validate_doc_update: string,
  views: JsonNode,
  autoupdate = true,
): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#put--db-_design-ddoc
  let req = self.hc.put(fmt"{self.baseUrl}/{db}/_design/{ddoc}")

  doAssert req.code in {Http201, Http202}
  req.body.parseJson

proc deleteDesignDoc*(self, db, ddoc) =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#delete--db-_design-ddoc

  let req = self.hc.delete(fmt"{self.baseUrl}/{db}/_design/{ddoc}")
  doAssert req.code == Http200

proc copyDesignDoc*(self, db, ddoc): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#copy--db-_design-ddoc

  let req = self.hc.request(fmt"{self.baseUrl}/{db}/_design/{ddoc}", httpMethod = "COPY")

  doAssert req.code == Http200
  req.body.parseJson

proc getDesignDocAtt*(self, db, ddoc, attname; headOnly: static[bool] = false, rev = ""): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#head--db-_design-ddoc-attname
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#get--db-_design-ddoc-attname
  var queryParams = newseq[DoubleStrTuple].createNadd([rev], getDocDefaults)

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/{ddoc}/{attname}?" & encodeQuery(queryParams),
    httpMethod =
    if headOnly: HttpHead
      else: HttpGet
    )

  doAssert req.code == Http200
  req.body.parseJson

proc uploadDesignDocAtt*(self, db, ddoc, attname; contentType, content: string, rev = "") {.captureDefaults.} =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#put--db-_design-ddoc-attname
  var queryParams = newseq[DoubleStrTuple]().createNadd([rev], getDocDefaults)

  let req = self.hc.request(
    fmt"{self.baseUrl}/{db}/{ddoc}/{attname}?" & encodeQuery(queryParams),
    httpMethod = HttpPut,
    headers = changeHeaders(self.hc.headers, [
      ("Content-Type", content),
      ("Content-Length", $content.len)
    ])
  )

  doAssert req.code in {Http201, Http202}

proc deleteDesignDocAtt*(self, db, ddoc; rev: string) {.captureDefaults.} =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#delete--db-_design-ddoc-attname
  let req = self.hc.delete(fmt"{self.baseUrl}/{db}/{ddoc}?rev={rev}")
  doAssert req.code in {Http200, Http202}

proc getDesignDocInfo*(self, db; ddoc: string): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/ddoc/common.html#get--db-_design-ddoc-_info

  let req = self.hc.get(fmt"{self.baseUrl}/{db}/_design/{ddoc}/_info")

  doAssert req.code == Http200
  req.body.parseJson

proc getView*(self, db, ddoc, view;
  conflicts = false,
  descending = false,
  startkey,
  endkey,
  startkey_docid,
  endkey_docid = newJObject(),
  group = false,
  group_level = -1,
  include_docs = false,
  attachments = false,
  att_encoding_info = false,
  inclusive_end = true,
  key = newJObject(),
  keys = newJObject(),
  limit = 0,
  reduce = true,
  skip = 0,
  sorted = true,
  stable = true,
  update = UVTrue,
  update_seq = false,
): JsonNode {.captureDefaults.} =
  ## https://docs.couchdb.org/en/stable/api/ddoc/views.html#get--db-_design-ddoc-_view-view
  var body = createNadd(%*{}, [
    conflicts,
    descending,
    startkey,
    endkey,
    startkey_docid,
    endkey_docid,
    group,
    group_level,
    include_docs,
    attachments,
    att_encoding_info,
    inclusive_end,
    key,
    keys,
    limit,
    reduce,
    skip,
    sorted,
    stable,
    update,
    update_seq,
  ], getViewDefaults)

  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_design/{ddoc}/_view/{view}", $body)
  doAssert req.code == Http200

  req.body.parseJson

proc getView*(self, db, ddoc, view; queries: JsonNode): JsonNode =
  ## https://docs.couchdb.org/en/stable/api/ddoc/views.html#get--db-_design-ddoc-_view-view
  let req = self.hc.post(fmt"{self.baseUrl}/{db}/_design/{ddoc}/_view/{view}", $ %* {"queries": queries})
  doAssert req.code == Http200

  req.body.parseJson

# TODO https://docs.couchdb.org/en/stable/api/ddoc/search.html#db-design-design-doc-search-index-name

# PARTIONED DATABASEs API ------------------------------------------------------------

# LOCAL DOCUMENTs API ------------------------------------------------------------