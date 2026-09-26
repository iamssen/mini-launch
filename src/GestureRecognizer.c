#include "GestureRecognizer.h"
#include <math.h>
int MLRecognize(MLGestureState *s, int count, double radius, double time) {
    if (count == 0 || !isfinite(radius) || !isfinite(time)) { *s = (MLGestureState){0}; return 0; }
    if (time < s->lastTime || time - s->lastTime > 0.4) *s = (MLGestureState){0};
    s->lastTime = time;
    if (s->fired) return 0;
    if (count != 5 || radius < 0.015) { s->baseline = 0; return 0; }
    if (!s->baseline) { s->baseline = radius; s->started = time; return 0; }
    if (time - s->started < 0.08) return 0;
    if (time - s->started > 2.0) { s->baseline = radius; s->started = time; return 0; }
    double ratio = radius / s->baseline;
    int result = ratio < 0.72 ? -1 : ratio > 1.32 ? 1 : 0;
    if (result) s->fired = true;
    return result;
}
