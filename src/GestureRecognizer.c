#include "GestureRecognizer.h"
#include <math.h>
int MLRecognize(MLGestureState *s, int count, double radius, double time) {
    if (count <= 0 || !isfinite(radius) || !isfinite(time)) { *s = (MLGestureState){0}; return 0; }
    if (time < s->lastTime || time - s->lastTime > 0.4) *s = (MLGestureState){0};
    s->lastTime = time;
    // 짧은 접촉 누락은 진행 상태를 보존하되 해당 프레임으로 판정하지 않습니다.
    if ((count != 4 && count != 5) || radius < 0.015) {
        s->paused = 1;
        if (s->baseline && time - s->lastValidTime > 0.12) *s = (MLGestureState){0};
        return 0;
    }
    if (s->paused && time - s->lastValidTime > 0.12) *s = (MLGestureState){0};
    s->lastTime = time;
    if (!s->baseline) {
        s->baseline = s->extremum = radius;
        s->started = time;
    } else if (s->count != count || s->paused) {
        // 접촉 수 변화로 생긴 거리 차이는 동작량에서 제외합니다.
        double scale = radius / s->lastRadius;
        s->baseline *= scale;
        s->extremum *= scale;
        s->started = time;
    }
    s->count = count;
    s->paused = 0;
    s->lastRadius = radius;
    s->lastValidTime = time;
    // 실행 이후에는 가장 모인/펼쳐진 위치에서 충분히 역행해야 반대 동작을 실행합니다.
    if (s->direction < 0) s->extremum = fmin(s->extremum, radius);
    if (s->direction > 0) s->extremum = fmax(s->extremum, radius);
    if (time - s->started < 0.08) return 0;
    if (!s->direction && time - s->started > 2.0) {
        s->baseline = s->extremum = radius; s->started = time; return 0;
    }
    double reference = s->direction ? s->extremum : s->baseline;
    double ratio = radius / reference;
    int result = s->direction >= 0 && ratio < 0.72 ? -1 :
                 s->direction <= 0 && ratio > 1.32 ? 1 : 0;
    if (result) {
        s->direction = result;
        s->extremum = radius;
        s->started = time;
    }
    return result;
}
