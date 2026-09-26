#ifndef ML_GESTURE_RECOGNIZER_H
#define ML_GESTURE_RECOGNIZER_H
#include <stdbool.h>
typedef struct { double baseline, started, lastTime; bool fired; } MLGestureState;
// 반환값: -1 모으기, +1 펼치기, 0 변화 없음. 손을 떼어야 다시 인식합니다.
int MLRecognize(MLGestureState *state, int count, double radius, double time);
#endif
