ARG BASE=ghcr.io/emqx/otp/base:ubuntu20.04
FROM $BASE

ARG ARCHIVE=otp_src.tar.gz
COPY $ARCHIVE .

ENV ERL_TOP="/usr/src/otp"
RUN set -ex \
    && mkdir -p $ERL_TOP \
    && tar -xzf $ARCHIVE -C $ERL_TOP --strip-components=1 \
    && rm -f $ARCHIVE \
    && cd $ERL_TOP \
    && ./otp_build autoconf \
    && ./configure --disable-hipe \
    && make -j$(nproc) \
    && make install \
    && erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell

RUN TESTSUITE_ROOT=/tests $ERL_TOP/otp_build tests

ARG REBAR3_VERSION="3.14.3-emqx-4"
ENV DOWNLOAD_URL='https://github.com/emqx/rebar3/releases/download'

RUN wget --no-verbose --no-check-certificate -O /usr/local/bin/rebar3 "${DOWNLOAD_URL}/${REBAR3_VERSION}/rebar3" \
    && chmod +x /usr/local/bin/rebar3 \
    && rebar3 --version

CMD ["erl"]
