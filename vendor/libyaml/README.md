# LibYAML

- 버전: 0.2.5
- 원본: https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz
- 원본 SHA-256: `c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4`
- 라이선스: MIT (`LICENSE`)
- 배포본의 `include/yaml.h`, `src/*.[ch]`를 포함했습니다. 중첩 깊이 제한을 위해 공식 커밋 `51843fe48257c6b7b6e70cdec1db634f64a40818`의 라이브러리 부분을 적용했습니다.
- 수정 원본: https://github.com/yaml/libyaml/commit/51843fe48257c6b7b6e70cdec1db634f64a40818
- `build-yaml.sh`에서 버전 상수를 지정하고 정적 라이브러리를 생성합니다.
- 사용자 환경의 Homebrew 라이브러리나 런타임 패키지 설치를 요구하지 않습니다.
