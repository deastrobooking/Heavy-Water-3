#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>

struct spa_pod *sysaudio_spa_format_audio_raw_build(struct spa_pod_builder *builder, uint32_t id, struct spa_audio_info_raw *info)
{
	return spa_format_audio_raw_build(builder, id, info);
}

typedef int (*pw_stream_connect_fn)(struct pw_stream *, enum spa_direction, uint32_t, enum pw_stream_flags, const struct spa_pod **, uint32_t);

int sysaudio_pw_stream_connect_playback(pw_stream_connect_fn connect_fn, struct pw_stream *stream, uint32_t rate, uint32_t channels)
{
	uint8_t buf[256];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
	struct spa_audio_info_raw info = SPA_AUDIO_INFO_RAW_INIT(
		.format = SPA_AUDIO_FORMAT_F32,
		.rate = rate,
		.channels = channels
	);
	const struct spa_pod *params[1];
	params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);

	return connect_fn(stream,
		PW_DIRECTION_OUTPUT,
		PW_ID_ANY,
		PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS,
		params, 1);
}

int sysaudio_pw_stream_connect_capture(pw_stream_connect_fn connect_fn, struct pw_stream *stream, uint32_t rate, uint32_t channels)
{
	uint8_t buf[256];
	struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
	struct spa_audio_info_raw info = SPA_AUDIO_INFO_RAW_INIT(
		.format = SPA_AUDIO_FORMAT_F32,
		.rate = rate,
		.channels = channels
	);
	const struct spa_pod *params[1];
	params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);

	return connect_fn(stream,
		PW_DIRECTION_INPUT,
		PW_ID_ANY,
		PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS,
		params, 1);
}

void sysaudio_pw_registry_add_listener(struct pw_registry *reg, struct spa_hook *reg_listener, struct pw_registry_events *events) {
	pw_registry_add_listener(reg, reg_listener, events, NULL);
}
