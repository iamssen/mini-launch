#ifndef ML_GESTURE_RECOGNIZER_H
#define ML_GESTURE_RECOGNIZER_H
typedef struct {
    double baseline, started, lastTime, lastRadius, lastValidTime, extremum;
    int count, direction;
    int paused;
} MLGestureState;
// 반환값: -1 모으기, +1 펼치기, 0 변화 없음. 접촉 중 반대 방향으로 전환할 수 있습니다.
int MLRecognize(MLGestureState *state, int count, double radius, double time);
#endif
