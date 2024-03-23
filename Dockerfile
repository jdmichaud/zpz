FROM nginx:1.23.1

RUN apt update
RUN apt install -y curl xz-utils less git

RUN curl -sOL https://ziglang.org/builds/zig-linux-x86_64-0.12.0-dev.3428+d8bb139da.tar.xz && \
  tar Jxf zig-linux-x86_64-0.12.0-dev.3428+d8bb139da.tar.xz

RUN git clone http://github.com/jdmichaud/zpz && \
  cd zpz && \
  git submodule init && \
  git submodule update && \
  ../zig-linux-x86_64-0.12.0-dev.3428+d8bb139da/zig build wasm -Doptimize=ReleaseSmall

RUN cp -r /zpz/web/* /usr/share/nginx/html && \
  cp --remove-destination /zpz/zig-out/bin/zpz6128.wasm /usr/share/nginx/html/
