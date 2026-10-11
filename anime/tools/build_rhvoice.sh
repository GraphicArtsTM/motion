#!/usr/bin/env bash
# Сборка RHVoice (русские голоса) из исходников в tools/rhvoice — нужно только для tts.py.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p rhvoice && cd rhvoice
[ -d src ] || git clone -q --depth=1 https://github.com/RHVoice/RHVoice.git src
cd src
git tag 1.16.0 2>/dev/null || true          # версия для CMake в мелком клоне
git submodule update --init --depth=1 -j 8 external/libs/sonic \
  $(git config -f .gitmodules --get-regexp 'submodule\.external/libs/boost.*\.path' | awk '{print $2}') \
  cmake/thirdParty/sanitizers cmake/thirdParty/CCache data/languages/Russian \
  data/voices/aleksandr-hq data/voices/anna data/voices/pavel data/voices/tatiana data/voices/artemiy data/voices/vitaliy-ng
# tclap не компилируется в C++20 из-за template-id в конструкторах копирования
sed -i 's/^\(\s*\)ValueArg<T>(const ValueArg<T>& rhs);/\1ValueArg(const ValueArg<T>\& rhs);/' src/third-party/tclap/tclap/ValueArg.h
sed -i 's/^\(\s*\)MultiArg<T>(const MultiArg<T>& rhs);/\1MultiArg(const MultiArg<T>\& rhs);/' src/third-party/tclap/tclap/MultiArg.h
INC=$(for d in $PWD/external/libs/boost/libs/*/include; do printf -- "-I%s " "$d"; done)
mkdir -p build && cd build
CXXFLAGS="$INC" CFLAGS="$INC" cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_DATA=OFF -Ddev=ON >/dev/null
make -j"$(nproc)" RHVoice-test >/dev/null
echo "готово: $(pwd)/src/test/RHVoice-test"
