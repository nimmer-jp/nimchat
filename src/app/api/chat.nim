import crown/core
import std/httpclient except Response
import std/[json, strutils, uri]

proc buildError(message: string, status = Http400): Response =
  jsonResponse(%*{
    "ok": false,
    "error": message
  }, status)

proc csvToList(input: string): seq[string] =
  for item in input.split(","):
    let normalized = item.strip()
    if normalized.len > 0:
      result.add(normalized)

proc isAllowedIp(currentIp: string, restrictionEnabled: bool, allowedIps: seq[
    string]): bool =
  if not restrictionEnabled or allowedIps.len == 0:
    return true

  if currentIp.len == 0:
    return false

  for allowed in allowedIps:
    if cmpIgnoreCase(currentIp, allowed) == 0:
      return true
  false

proc parseHistory(historyRaw: string): JsonNode =
  if historyRaw.strip().len == 0:
    return newJArray()

  try:
    let parsed = parseJson(historyRaw)
    if parsed.kind == JArray:
      return parsed
  except JsonParsingError:
    discard

  newJArray()

proc buildMessages(historyRaw, prompt: string): JsonNode =
  result = newJArray()
  let history = parseHistory(historyRaw)

  if history.kind == JArray:
    var start = 0
    if history.len > 20:
      start = history.len - 20

    for idx in start ..< history.len:
      let msg = history[idx]
      if msg.kind != JObject:
        continue
      if not msg.hasKey("role") or not msg.hasKey("content"):
        continue
      if msg["role"].kind != JString or msg["content"].kind != JString:
        continue
      let role = msg["role"].getStr().strip().toLowerAscii()
      let content = msg["content"].getStr().strip()
      if content.len == 0:
        continue
      if role notin ["user", "assistant", "system"]:
        continue
      result.add(%*{
        "role": role,
        "content": content
      })

  result.add(%*{
    "role": "user",
    "content": prompt.strip()
  })

proc extractAssistantText(data: JsonNode): string =
  if data.kind != JObject:
    return ""

  if data.hasKey("choices") and data["choices"].kind == JArray and data["choices"].len > 0:
    let first = data["choices"][0]
    if first.kind == JObject:
      if first.hasKey("message") and first["message"].kind == JObject:
        let message = first["message"]
        if message.hasKey("content") and message["content"].kind == JString:
          let content = message["content"].getStr().strip()
          if content.len > 0:
            return content
      if first.hasKey("text") and first["text"].kind == JString:
        let content = first["text"].getStr().strip()
        if content.len > 0:
          return content

  if data.hasKey("message") and data["message"].kind == JObject:
    let message = data["message"]
    if message.hasKey("content") and message["content"].kind == JString:
      let content = message["content"].getStr().strip()
      if content.len > 0:
        return content

  if data.hasKey("response") and data["response"].kind == JString:
    let content = data["response"].getStr().strip()
    if content.len > 0:
      return content

  if data.hasKey("output_text") and data["output_text"].kind == JString:
    let content = data["output_text"].getStr().strip()
    if content.len > 0:
      return content

  ""

proc normalizedEndpointPath(rawPath: string): string =
  result = rawPath.strip()
  if result.len == 0:
    return "/"
  if result.len > 1 and result.endsWith("/"):
    result = result[0 ..< result.high]
  if result.len == 0:
    return "/"

proc endpointWithPath(baseUri: Uri, routePath: string): string =
  var updated = baseUri
  updated.path = routePath
  $updated

proc addEndpointCandidate(candidates: var seq[string], endpoint: string) =
  let normalized = endpoint.strip()
  if normalized.len == 0 or normalized in candidates:
    return
  candidates.add(normalized)

proc buildEndpointCandidates(endpoint: string): seq[string] =
  try:
    let parsed = parseUri(endpoint)
    let path = normalizedEndpointPath(parsed.path)

    if path == "/":
      for routePath in [
          "/v1/chat/completions",
          "/chat/completions",
          "/v1/completions",
          "/completions",
          "/"
        ]:
        result.addEndpointCandidate(endpointWithPath(parsed, routePath))
      return

    if path == "/v1":
      for routePath in ["/v1/chat/completions", "/v1/completions", "/v1"]:
        result.addEndpointCandidate(endpointWithPath(parsed, routePath))
      return

    result.addEndpointCandidate(endpointWithPath(parsed, path))
  except CatchableError:
    discard

  if result.len == 0:
    result.add(endpoint)

proc isLikelyMissingRoute(statusCode: int, responseBody: string): bool =
  if statusCode != 404:
    return false

  let normalized = responseBody.strip().toLowerAscii()
  if normalized.len == 0:
    return true
  if normalized == "not found":
    return true
  if normalized == """{"detail":"not found"}""":
    return true
  if normalized == """{"error":"not found"}""":
    return true
  if normalized.startsWith("<!doctype html") or normalized.startsWith("<html"):
    return normalized.contains("404")
  false

proc requestOnce(endpoint, payload: string): tuple[statusCode: int, responseBody: string] =
  var client = newHttpClient(timeout = 120_000)
  defer:
    client.close()

  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Accept": "application/json"
  })

  let upstreamResponse = client.request(
    endpoint,
    httpMethod = HttpPost,
    body = payload
  )

  (int(upstreamResponse.code), upstreamResponse.body)

proc requestLocalLlm(endpoint, model, prompt, historyRaw: string): JsonNode =
  let messages = buildMessages(historyRaw, prompt)

  var payload = %*{
    "messages": messages,
    "stream": false
  }
  if model.len > 0:
    payload["model"] = %model

  let endpointCandidates = buildEndpointCandidates(endpoint)
  var triedEndpoints = newJArray()
  var lastStatus = 0
  var lastBody = ""

  for candidate in endpointCandidates:
    triedEndpoints.add(%candidate)
    let (statusCode, responseBody) = requestOnce(candidate, $payload)

    if endpointCandidates.len > 1 and isLikelyMissingRoute(statusCode, responseBody):
      lastStatus = statusCode
      lastBody = responseBody
      continue

    if statusCode < 200 or statusCode >= 300:
      return %*{
        "ok": false,
        "error": "LLMエンドポイントがエラーを返しました。",
        "upstreamStatus": statusCode,
        "upstreamBody": responseBody,
        "triedEndpoints": triedEndpoints
      }

    let parsed = parseJson(responseBody)
    let assistant = extractAssistantText(parsed)
    if assistant.len == 0:
      return %*{
        "ok": false,
        "error": "LLMレスポンス形式を解釈できませんでした。",
        "upstreamStatus": statusCode,
        "triedEndpoints": triedEndpoints
      }

    return %*{
      "ok": true,
      "assistant": assistant
    }

  %*{
    "ok": false,
    "error": "LLMエンドポイントが見つかりませんでした。接続先URLを確認してください。",
    "upstreamStatus": lastStatus,
    "upstreamBody": lastBody,
    "triedEndpoints": triedEndpoints
  }

proc get*(req: Request): Response =
  discard req
  jsonResponse(%*{
    "ok": true,
    "message": "Use POST /api/chat with endpoint, prompt, model, historyJson."
  })

proc post*(req: Request): Response =
  let endpoint = req.params.getOrDefault("endpoint", "").strip()
  let model = req.params.getOrDefault("model", "").strip()
  let prompt = req.params.getOrDefault("prompt", "").strip()
  let historyRaw = req.params.getOrDefault("historyJson", "[]")

  if endpoint.len == 0:
    return buildError("接続先URLが未設定です。")
  if not (endpoint.startsWith("http://") or endpoint.startsWith("https://")):
    return buildError("接続先URLは http:// または https:// で始めてください。")
  if prompt.len == 0:
    return buildError("メッセージが空です。")

  let restrictionEnabled =
    req.params.getOrDefault("ipRestrictionEnabled", "false").strip().toLowerAscii() == "true"
  let allowedIps = csvToList(req.params.getOrDefault("allowedIps", ""))
  let clientIp = req.params.getOrDefault("clientIp", "").strip()

  if not isAllowedIp(clientIp, restrictionEnabled, allowedIps):
    return buildError(
      "このIPアドレスからはアクセスできません。初回設定の許可IPを確認してください。",
      Http403
    )

  try:
    let apiResult = requestLocalLlm(endpoint, model, prompt, historyRaw)
    if apiResult.hasKey("ok") and apiResult["ok"].kind == JBool and not apiResult["ok"].getBool():
      let status = if apiResult.hasKey("upstreamStatus") and apiResult["upstreamStatus"].kind == JInt:
        HttpCode(apiResult["upstreamStatus"].getInt())
      else:
        Http502
      return jsonResponse(apiResult, status)
    return jsonResponse(apiResult)
  except OSError as ex:
    return buildError(
      "LLM接続先へ接続できませんでした: " & ex.msg,
      Http502
    )
  except HttpRequestError as ex:
    return buildError(
      "LLM接続先へ接続できませんでした: " & ex.msg,
      Http502
    )
  except JsonParsingError:
    return buildError(
      "LLMの応答がJSONではありません。エンドポイントURLを確認してください。",
      Http502
    )
  except CatchableError as ex:
    return buildError(
      "予期しないエラーが発生しました: " & ex.msg,
      Http500
    )
