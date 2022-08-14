FROM nginx:1.23.1

RUN apt update
RUN apt install -y curl xz-utils less zip

RUN curl -sOL https://github.com/marler8997/zigup/releases/download/v2022_08_25/zigup.ubuntu-latest-x86_64.zip && \
  unzip zigup.ubuntu-latest-x86_64.zip && \
  chmod +x zigup && \
  zigup 0.10.0-dev.3842+36f4f32fa



COPY web /usr/share/nginx/html
COPY zig-out/lib/zpz6128.wasm /usr/share/nginx/html