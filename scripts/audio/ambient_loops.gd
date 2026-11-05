class_name AmbientLoops
extends RefCounted
## Helpers for looping ambience files.


## Makes an imported sound (Ogg/MP3/WAV) loop, so ambience works without ticking
## "Loop" in each file's import settings. Returns the same stream. Null in, null out.
static func looped(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.set("loop", true)
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return stream
