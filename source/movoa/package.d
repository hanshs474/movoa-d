/**
 * Official D SDK for Movoa (https://movoa.ai), the AI video generator with sound.
 *
 * ---
 * import movoa;
 * auto r = generateVideo("a paper boat drifting down a rain gutter, low angle");
 * if (r.ok) writeln(r.url); else writeln(r.reason, ": ", r.message);
 * ---
 *
 * Set `Options.apiKey` or MOVOA_API_KEY; create a key at
 * https://movoa.ai/settings/apikeys. Uses std.net.curl.
 */
module movoa;

import core.thread : Thread;
import core.time : msecs, seconds;
import std.algorithm : canFind;
import std.datetime.systime : Clock;
import std.json;
import std.net.curl : HTTP;
import std.process : environment;
import std.string : strip, toLower;

enum Reason { none, auth, quota, plan, busy, rejected, validation, failed, timeout, other }

struct Result { bool ok; string url; Reason reason; string message; int status; }

struct Status {
    bool ok;
    string id;
    string status;
    string videoUrl;
    string errorMessage;
    string failureKind;
    Reason reason;
    string message;
}

struct Options
{
    string model;               /// default minimax-h3
    string imageUrl;            /// optional first-frame URL (photo to video)
    JSONValue options;          /// optional overrides: duration, resolution, aspect_ratio
    string apiKey;              /// default MOVOA_API_KEY
    int pollMillis = 10000;
    int timeoutSeconds = 1800;
}

__gshared string baseUrl = "https://movoa.ai";

struct Reply { int status; JSONValue body; }

__gshared Reply delegate(string url, string body, string key) transport;

enum keysUrl = "https://movoa.ai/settings/apikeys";
enum defaultVideoModel = "minimax-h3";

shared static this()
{
    transport = (string url, string body, string key) {
        auto http = HTTP(url);
        http.method = HTTP.Method.post;
        http.addRequestHeader("Authorization", "Bearer " ~ key);
        http.addRequestHeader("Content-Type", "application/json");
        http.addRequestHeader("User-Agent", "movoa-d/0.1.0");
        http.postData = body;
        ubyte[] buf;
        http.onReceive = (ubyte[] d) { buf ~= d; return d.length; };
        http.perform();
        JSONValue parsed;
        try parsed = parseJSON(cast(string) buf.idup);
        catch (Exception) parsed = JSONValue.init;
        return Reply(http.statusLine.code, parsed);
    };
}

private bool has(const JSONValue v, string k)
{
    return v.type == JSONType.object && (k in v.object) !is null;
}

private string str(const JSONValue v, string k)
{
    return has(v, k) && v[k].type == JSONType.string ? v[k].str : "";
}

private long num(const JSONValue v, string k, long fallback = 0)
{
    return has(v, k) && (v[k].type == JSONType.integer || v[k].type == JSONType.uinteger) ? v[k].integer : fallback;
}

Reason classify(int status, JSONValue body)
{
    auto code = num(body, "code", 0);
    auto msg = str(body, "message").toLower;
    auto data = has(body, "data") ? body["data"] : JSONValue.init;
    auto reason = str(data, "reason");
    if (status == 401 || (code == -1 && (msg.canFind("no auth") || reason == "invalid_api_key"))) return Reason.auth;
    if (code == -2 || code == -3) return Reason.rejected;
    if (reason == "insufficient_credits") return Reason.quota;
    if (reason == "plan_required") return Reason.plan;
    if (reason == "concurrency") return Reason.busy;
    if (status == 400) return Reason.validation;
    return Reason.other;
}

private Result fail(Reason r, string msg, int status = 0) { return Result(false, null, r, "movoa: " ~ msg, status); }

private Result call(string path, JSONValue body, string apiKey, out JSONValue answer)
{
    auto key = apiKey.length ? apiKey : environment.get("MOVOA_API_KEY", "");
    if (key.length == 0) return fail(Reason.auth, "an API key is required; create one at " ~ keysUrl);
    Reply r;
    try r = transport(baseUrl ~ path, body.toString, key);
    catch (Exception e) return fail(Reason.other, e.msg);
    if (r.status == 200 && r.body.type == JSONType.object && num(r.body, "code", -1) == 0)
    {
        answer = r.body;
        return Result(true);
    }
    auto msg = str(r.body, "message");
    if (!msg.length) msg = str(r.body, "error");
    if (!msg.length) msg = "HTTP error";
    return fail(classify(r.status, r.body), msg, r.status);
}

Result submit(string prompt, string model = defaultVideoModel, Options o = Options.init)
{
    if (prompt.strip.length == 0) return fail(Reason.validation, "prompt is required");
    JSONValue opts = JSONValue.emptyObject;
    if (o.options.type == JSONType.object)
    {
        foreach (k, v; o.options.object) opts[k] = v;
    }
    opts["sound"] = true;
    string scene = "text-to-video";
    if (o.imageUrl.length)
    {
        scene = "image-to-video";
        opts["image_input"] = JSONValue([JSONValue(o.imageUrl)]);
    }
    JSONValue body = [
        "provider": JSONValue("auto"),
        "mediaType": JSONValue("video"),
        "model": JSONValue(model.length ? model : defaultVideoModel),
        "scene": JSONValue(scene),
        "prompt": JSONValue(prompt),
        "options": opts,
    ];
    JSONValue a;
    auto r = call("/api/ai/generate", body, o.apiKey, a);
    if (!r.ok) return r;
    auto id = has(a, "data") ? str(a["data"], "id") : "";
    if (!id.length) return fail(Reason.other, "the service returned no id");
    return Result(true, id);
}

Status status(string id, string apiKey = null)
{
    JSONValue a;
    auto r = call("/api/ai/query", JSONValue(["taskId": id]), apiKey, a);
    if (!r.ok) { Status s; s.reason = r.reason; s.message = r.message; return s; }
    auto d = has(a, "data") ? a["data"] : JSONValue.emptyObject;
    string vurl = "";
    if (has(d, "videos") && d["videos"].type == JSONType.array && d["videos"].array.length > 0)
    {
        if (d["videos"][0].type == JSONType.string) vurl = d["videos"][0].str;
    }
    return Status(true, str(d, "id"), str(d, "status"), vurl, str(d, "errorMessage"), str(d, "failureKind"));
}

long credits(string apiKey = null, Reason* reason = null)
{
    JSONValue a;
    auto r = call("/api/user/get-user-credits", JSONValue.emptyObject, apiKey, a);
    if (r.ok && has(a, "data") && has(a["data"], "remainingCredits"))
        return a["data"]["remainingCredits"].integer;
    if (reason) *reason = r.reason;
    return -1;
}

Result wait(string id, Options o = Options.init)
{
    auto deadline = Clock.currTime + o.timeoutSeconds.seconds;
    while (Clock.currTime < deadline)
    {
        Thread.sleep(o.pollMillis.msecs);
        auto s = status(id, o.apiKey);
        if (!s.ok)
        {
            if (s.reason == Reason.auth) return Result(false, null, s.reason, s.message);
            continue;
        }
        if (s.status == "success" && s.videoUrl.length) return Result(true, s.videoUrl);
        if (s.status == "failed" || s.status == "canceled")
            return fail(Reason.failed, s.errorMessage.length ? s.errorMessage : "the run failed");
    }
    return fail(Reason.timeout, "deadline passed; task " ~ id ~ " may still finish in your Movoa library");
}

Result generateVideo(string prompt, Options o = Options.init)
{
    auto r = submit(prompt, o.model.length ? o.model : defaultVideoModel, o);
    return r.ok ? wait(r.url, o) : r;
}

unittest
{
    JSONValue[] bodies;
    string[] urls;
    Reply[] replies;
    auto saved = transport;
    scope (exit) transport = saved;
    transport = (string url, string body, string key) {
        urls ~= url;
        bodies ~= parseJSON(body);
        auto r = replies[0];
        replies = replies[1 .. $];
        return r;
    };
    Reply ok(string j) { return Reply(200, parseJSON(j)); }

    replies = [
        ok(`{"code":0,"data":{"id":"t1","status":"pending"}}`),
        ok(`{"code":0,"data":{"status":"processing"}}`),
        ok(`{"code":0,"data":{"status":"success","videos":["https://cdn.movoa.ai/v1.mp4"]}}`),
    ];
    Options o = { apiKey: "sk-x", pollMillis: 0 };
    o.options = JSONValue(["duration": 6]);
    auto v = generateVideo("a paper boat", o);
    assert(v.ok && v.url == "https://cdn.movoa.ai/v1.mp4");
    assert(urls[0].canFind("/api/ai/generate") && bodies[0]["model"].str == "minimax-h3");
    assert(bodies[0]["options"]["sound"].boolean == true);
    assert(urls[1].canFind("/api/ai/query") && bodies[1]["taskId"].str == "t1");

    replies = [ok(`{"code":0,"data":{"remainingCredits":42}}`)];
    assert(credits("sk-x") == 42);
}
