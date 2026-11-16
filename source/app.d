/// movoa "a prompt"      -> clip URL (MiniMax H3 with sound)
/// movoa --credits       -> remaining credits (set MOVOA_API_KEY)
import std.stdio;
import movoa;

int main(string[] args)
{
    if (args.length > 1 && args[1] == "--credits")
    {
        Reason why;
        auto n = credits(null, &why);
        if (n < 0) { stderr.writeln(why, ": could not read credits"); return why == Reason.auth ? 3 : 1; }
        writeln(n);
        return 0;
    }
    if (args.length < 2) { stderr.writeln(`usage: movoa "prompt" | movoa --credits`); return 2; }
    auto r = generateVideo(args[1]);
    if (!r.ok) { stderr.writeln(r.reason, ": ", r.message); return r.reason == Reason.auth ? 3 : 1; }
    writeln(r.url);
    return 0;
}
