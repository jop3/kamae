#!/usr/bin/env python3
"""Drops the frames a sequence render drew before its film starts.

The render shows every pose once before filming (SequencePlayer.prepare) and the movie writer
records every frame drawn; the render notes which ones in prepare_frames.txt ("first last":
frames first..last-1). They are removed and the rest numbered on without a gap.
    python3 tools/drop_prepare_frames.py <frames dir>
"""
import os
import sys

d = sys.argv[1]
note = os.path.join(d, "prepare_frames.txt")
if os.path.exists(note):
    first, last = map(int, open(note).read().split())
    n = last - first
    for i in range(first, last):
        p = os.path.join(d, "f%08d.png" % i)
        if os.path.exists(p):
            os.remove(p)
    i = last
    while os.path.exists(os.path.join(d, "f%08d.png" % i)):
        os.rename(os.path.join(d, "f%08d.png" % i), os.path.join(d, "f%08d.png" % (i - n)))
        i += 1
    os.remove(note)
