#!/usr/bin/env python3
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
marker = "EasyRPG-PS2 runtime v2: underrun-safe ring accounting"
if marker in s:
    print("[audsrv v2] already patched")
    raise SystemExit(0)


def rep(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"audsrv v2: {label}: expected 1 anchor, found {n}")
    s = s.replace(old, new, 1)


rep(
    "static int writepos;\n",
    """static int writepos;
/** EasyRPG-PS2 runtime v2: underrun-safe ring accounting.
 * readpos == writepos is no longer ambiguous: ringbuf_used distinguishes
 * a truly empty queue from a full one. */
static int ringbuf_used = 0;
/** Source bytes consumed by one 512-sample render iteration. */
static int core1_feed_size = 0;
""",
    "ring globals")

rep(
    """int audsrv_stop_audio()
{
\t/* audio is still playing, just mute */
\tplaying = 0;
\tupdate_volume();
\tfillbuf_threshold = 0;

\treturn AUDSRV_ERR_NOERROR;
}
""",
    """int audsrv_stop_audio()
{
\tint intr_state;

\tplaying = 0;
\tupdate_volume();
\tfillbuf_threshold = 0;

\tCpuSuspendIntr(&intr_state);
\treadpos = 0;
\twritepos = 0;
\tringbuf_used = 0;
\tCpuResumeIntr(intr_state);

\tmemset(ringbuf, '\\0', ringbuf_size);
\tmemset(rendered_left, '\\0', sizeof(rendered_left));
\tmemset(rendered_right, '\\0', sizeof(rendered_right));

\treturn AUDSRV_ERR_NOERROR;
}
""",
    "stop clears queue")

rep(
    """int audsrv_set_format(int freq, int bits, int channels)
{
\tint feed_size;
""",
    """int audsrv_set_format(int freq, int bits, int channels)
{
\tint feed_size;
\tint intr_state;
""",
    "set_format intr state")

rep(
    """\t/* set ring buffer size to 10 iterations worth of data (~50 ms) */
\tfeed_size = ((512 * core1_freq) / 48000) << core1_sample_shift;
\tringbuf_size = feed_size * 10;

\twritepos = 0;
\treadpos = (feed_size * 5) & ~3;
""",
    """\t/* set ring buffer size to 10 iterations worth of data (~50 ms) */
\tfeed_size = ((512 * core1_freq) / 48000) << core1_sample_shift;
\tcore1_feed_size = feed_size;
\tringbuf_size = feed_size * 10;

\t/* Start genuinely empty instead of making unwritten memory look queued. */
\tCpuSuspendIntr(&intr_state);
\twritepos = 0;
\treadpos = 0;
\tringbuf_used = 0;
\tCpuResumeIntr(intr_state);
\tmemset(ringbuf, '\\0', ringbuf_size);
""",
    "set_format empty queue")

rep(
    """int audsrv_available()
{
\tif (writepos <= readpos)
\t{
\t\treturn readpos - writepos;
\t}
\telse
\t{
\t\treturn (ringbuf_size - (writepos - readpos));
\t}
}
""",
    """int audsrv_available()
{
\tint intr_state;
\tint available;

\tCpuSuspendIntr(&intr_state);
\tavailable = ringbuf_size - ringbuf_used;
\tCpuResumeIntr(intr_state);
\treturn available;
}
""",
    "available accounting")

rep(
    """int audsrv_queued()
{
\tif (writepos < readpos)
\t{
\t\treturn (ringbuf_size - (readpos - writepos));
\t}
\telse
\t{
\t\treturn writepos - readpos;
\t}
}
""",
    """int audsrv_queued()
{
\tint intr_state;
\tint queued;

\tCpuSuspendIntr(&intr_state);
\tqueued = ringbuf_used;
\tCpuResumeIntr(intr_state);
\treturn queued;
}
""",
    "queued accounting")

rep(
    """int audsrv_play_audio(const char *buf, int buflen)
{
\tint sent = 0;
""",
    """int audsrv_play_audio(const char *buf, int buflen)
{
\tint sent = 0;
\tint intr_state;
""",
    "play_audio intr state")

rep(
    """\twhile (buflen > 0)
\t{
\t\tint copy = buflen;
\t\tif (writepos >= readpos)
\t\t{
\t\t\tcopy = MIN(ringbuf_size - writepos, buflen);
\t\t}

\t\tmemcpy(ringbuf + writepos, buf, copy);
\t\tbuf = buf + copy;
\t\tbuflen = buflen - copy;
\t\tsent = sent + copy;

\t\twritepos = writepos + copy;
\t\tif (writepos >= ringbuf_size)
\t\t{
\t\t\t/* rewind */
\t\t\twritepos = 0;
\t\t}
\t}
""",
    """\twhile (buflen > 0)
\t{
\t\tint copy = MIN(ringbuf_size - writepos, buflen);

\t\tmemcpy(ringbuf + writepos, buf, copy);
\t\tbuf = buf + copy;
\t\tbuflen = buflen - copy;
\t\tsent = sent + copy;

\t\tCpuSuspendIntr(&intr_state);
\t\twritepos = writepos + copy;
\t\tif (writepos >= ringbuf_size)
\t\t{
\t\t\twritepos = 0;
\t\t}
\t\tringbuf_used += copy;
\t\tif (ringbuf_used > ringbuf_size)
\t\t{
\t\t\tringbuf_used = ringbuf_size;
\t\t}
\t\tCpuResumeIntr(intr_state);
\t}
""",
    "play_audio publish bytes")

rep(
    """\t\tif (playing && upsampler != NULL)
\t\t{
\t\t\tup.src = (const unsigned char *)ringbuf + readpos;
\t\t\tup.left = rendered_left;
\t\t\tup.right = rendered_right;
\t\t\tstep = upsampler(&up);

\t\t\treadpos = readpos + step;
\t\t\tif (readpos >= ringbuf_size)
\t\t\t{
\t\t\t\t/* wrap around */
\t\t\t\treadpos = 0;
\t\t\t}
\t\t}
\t\telse
\t\t{
\t\t\t/* not playing */
\t\t\tmemset(rendered_left, '\\0', sizeof(rendered_left));
\t\t\tmemset(rendered_right, '\\0', sizeof(rendered_right));
\t\t}
""",
    """\t\t/* On underrun, output silence and DO NOT advance readpos. */
\t\tif (playing && upsampler != NULL && audsrv_queued() >= core1_feed_size)
\t\t{
\t\t\tup.src = (const unsigned char *)ringbuf + readpos;
\t\t\tup.left = rendered_left;
\t\t\tup.right = rendered_right;
\t\t\tstep = upsampler(&up);

\t\t\tCpuSuspendIntr(&intr_state);
\t\t\treadpos = readpos + step;
\t\t\tif (readpos >= ringbuf_size)
\t\t\t{
\t\t\t\treadpos = 0;
\t\t\t}
\t\t\tringbuf_used -= step;
\t\t\tif (ringbuf_used < 0)
\t\t\t{
\t\t\t\tringbuf_used = 0;
\t\t\t}
\t\t\tCpuResumeIntr(intr_state);
\t\t}
\t\telse
\t\t{
\t\t\tmemset(rendered_left, '\\0', sizeof(rendered_left));
\t\t\tmemset(rendered_right, '\\0', sizeof(rendered_right));
\t\t}
""",
    "play thread underrun")

p.write_text(s, encoding="utf-8", newline="\n")
print("[audsrv v2] patched underrun/full-empty accounting")
