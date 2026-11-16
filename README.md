# movoa (D SDK)

Unlimited AI video generator with sound: on paid plans the tenth take of a shot costs what the first did, and your first clip is free to make right now. This is the official D SDK for [Movoa](https://movoa.ai/?utm_source=dub&utm_medium=package): turn a prompt into [text to video](https://movoa.ai/video/text-to-video) or a still into [photo to video](https://movoa.ai/video/photo-to-video), with every clip returned as [AI video with audio](https://movoa.ai/video/ai-video-with-audio).

## Install

`dub.json`:

```json
{
  "dependencies": {
    "movoa": "~>0.1.0"
  }
}
```

## API key

Sign in on [movoa.ai](https://movoa.ai/?utm_source=dub&utm_medium=package), create a key at [movoa.ai/settings/apikeys](https://movoa.ai/settings/apikeys), and export `MOVOA_API_KEY=sk-...`.

Runs cost credits on your Movoa account, at the prices on [movoa.ai/pricing](https://movoa.ai/pricing).

## Use

```d
import std.stdio;
import movoa;

void main()
{
    auto r = generateVideo("a paper boat drifting down a rain gutter, low angle");
    if (r.ok) writeln(r.url);
    else writeln(r.reason, ": ", r.message);
}
```

Supported models include `minimax-h3` (default), [Seedance 2.5](https://movoa.ai/video/seedance-2-5), `seedance-2`, `seedance-2-fast`, `seedance-2-mini`, and [Veo 3](https://movoa.ai/video/google-veo-3).

## License

MIT
