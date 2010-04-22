#!/usr/bin/env escript
%% -*- erlang -*-

% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

default_config() ->
    test_util:build_file("etc/couchdb/default_dev.ini").

test_db_name() ->
    <<"couch_test_atts_compression">>.

main(_) ->
    test_util:init_code_path(),

    etap:plan(78),
    case (catch test()) of
        ok ->
            etap:end_tests();
        Other ->
            etap:diag(io_lib:format("Test died abnormally: ~p", [Other])),
            etap:bail(Other)
    end,
    ok.

test() ->
    couch_server_sup:start_link([default_config()]),
    put(addr, couch_config:get("httpd", "bind_address", "127.0.0.1")),
    put(port, couch_config:get("httpd", "port", "5984")),
    application:start(inets),
    timer:sleep(1000),
    couch_server:delete(test_db_name(), []),
    couch_db:create(test_db_name(), []),

    couch_config:set("attachments", "compression_level", "8"),
    couch_config:set("attachments", "compressible_types", "text/*"),

    create_1st_text_att(),
    create_1st_png_att(),
    create_2nd_text_att(),
    create_2nd_png_att(),

    tests_for_1st_text_att(),
    tests_for_1st_png_att(),
    tests_for_2nd_text_att(),
    tests_for_2nd_png_att(),

    create_already_compressed_att(db_url() ++ "/doc_comp_att", "readme.txt"),
    test_already_compressed_att(db_url() ++ "/doc_comp_att", "readme.txt"),

    test_create_already_compressed_att_with_invalid_content_encoding(
        db_url() ++ "/doc_att_deflate",
        "readme.txt",
        zlib:compress(test_text_data()),
        "deflate"
    ),

    test_create_already_compressed_att_with_invalid_content_encoding(
        db_url() ++ "/doc_att_compress",
        "readme.txt",
        % Note: As of OTP R13B04, it seems there's no LZW compression
        % (i.e. UNIX compress utility implementation) lib in OTP.
        % However there's a simple working Erlang implementation at:
        % http://scienceblogs.com/goodmath/2008/01/simple_lempelziv_compression_i.php
        test_text_data(),
        "compress"
    ),

    timer:sleep(3000), % to avoid mochiweb socket closed exceptions
    couch_server:delete(test_db_name(), []),
    couch_server_sup:stop(),
    ok.

db_url() ->
    "http://" ++ get(addr) ++ ":" ++ get(port) ++ "/" ++
    binary_to_list(test_db_name()).

create_1st_text_att() ->
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        put,
        {db_url() ++ "/testdoc1/readme.txt", [],
        "text/plain", test_text_data()},
        [],
        [{sync, true}]),
    etap:is(Code, 201, "Created text attachment using the standalone api"),
    ok.

create_1st_png_att() ->
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        put,
        {db_url() ++ "/testdoc2/icon.png", [],
        "image/png", test_png_data()},
        [],
        [{sync, true}]),
    etap:is(Code, 201, "Created png attachment using the standalone api"),
    ok.

% create a text attachment using the non-standalone attachment api
create_2nd_text_att() ->
    DocJson = {[
        {<<"_attachments">>, {[
            {<<"readme.txt">>, {[
                {<<"content_type">>, <<"text/plain">>},
                {<<"data">>, base64:encode(test_text_data())}
            ]}
        }]}}
    ]},
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        put,
        {db_url() ++ "/testdoc3", [],
        "application/json", list_to_binary(couch_util:json_encode(DocJson))},
        [],
        [{sync, true}]),
    etap:is(Code, 201, "Created text attachment using the non-standalone api"),
    ok.

% create a png attachment using the non-standalone attachment api
create_2nd_png_att() ->
    DocJson = {[
        {<<"_attachments">>, {[
            {<<"icon.png">>, {[
                {<<"content_type">>, <<"image/png">>},
                {<<"data">>, base64:encode(test_png_data())}
            ]}
        }]}}
    ]},
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        put,
        {db_url() ++ "/testdoc4", [],
        "application/json", list_to_binary(couch_util:json_encode(DocJson))},
        [],
        [{sync, true}]),
    etap:is(Code, 201, "Created png attachment using the non-standalone api"),
    ok.

create_already_compressed_att(DocUri, AttName) ->
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        put,
        {DocUri ++ "/" ++ AttName, [{"Content-Encoding", "gzip"}],
        "text/plain", zlib:gzip(test_text_data())},
        [],
        [{sync, true}]),
    etap:is(
        Code,
        201,
        "Created already compressed attachment using the standalone api"
    ),
    ok.

tests_for_1st_text_att() ->
    test_get_1st_text_att_with_accept_encoding_gzip(),
    test_get_1st_text_att_without_accept_encoding_header(),
    test_get_1st_text_att_with_accept_encoding_deflate(),
    test_get_1st_text_att_with_accept_encoding_deflate_only(),
    test_get_doc_with_1st_text_att(),
    test_1st_text_att_stub().

tests_for_1st_png_att() ->
    test_get_1st_png_att_without_accept_encoding_header(),
    test_get_1st_png_att_with_accept_encoding_gzip(),
    test_get_1st_png_att_with_accept_encoding_deflate(),
    test_get_doc_with_1st_png_att(),
    test_1st_png_att_stub().

tests_for_2nd_text_att() ->
    test_get_2nd_text_att_with_accept_encoding_gzip(),
    test_get_2nd_text_att_without_accept_encoding_header(),
    test_get_doc_with_2nd_text_att(),
    test_2nd_text_att_stub().

tests_for_2nd_png_att() ->
    test_get_2nd_png_att_without_accept_encoding_header(),
    test_get_2nd_png_att_with_accept_encoding_gzip(),
    test_get_doc_with_2nd_png_att(),
    test_2nd_png_att_stub().

test_get_1st_text_att_with_accept_encoding_gzip() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc1/readme.txt", [{"Accept-Encoding", "gzip"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, true, "received body is gziped"),
    Uncompressed = binary_to_list(zlib:gunzip(list_to_binary(Body))),
    etap:is(
        Uncompressed,
        test_text_data(),
        "received data for the 1st text attachment is ok"
    ),
    ok.

test_get_1st_text_att_without_accept_encoding_header() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc1/readme.txt", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_text_data(),
        "received data for the 1st text attachment is ok"
    ),
    ok.

test_get_1st_text_att_with_accept_encoding_deflate() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc1/readme.txt", [{"Accept-Encoding", "deflate"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    Deflated = lists:member({"content-encoding", "deflate"}, Headers),
    etap:is(Deflated, false, "received body is not deflated"),
    etap:is(
        Body,
        test_text_data(),
        "received data for the 1st text attachment is ok"
    ),
    ok.

test_get_1st_text_att_with_accept_encoding_deflate_only() ->
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        get,
        {db_url() ++ "/testdoc1/readme.txt",
            [{"Accept-Encoding", "deflate, *;q=0"}]},
        [],
        [{sync, true}]),
    etap:is(
        Code,
        406,
        "HTTP response code is 406 for an unsupported content encoding request"
    ),
    ok.

test_get_1st_png_att_without_accept_encoding_header() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc2/icon.png", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_png_data(),
        "received data for the 1st png attachment is ok"
    ),
    ok.

test_get_1st_png_att_with_accept_encoding_gzip() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc2/icon.png", [{"Accept-Encoding", "gzip"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_png_data(),
        "received data for the 1st png attachment is ok"
    ),
    ok.

test_get_1st_png_att_with_accept_encoding_deflate() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc2/icon.png", [{"Accept-Encoding", "deflate"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Deflated = lists:member({"content-encoding", "deflate"}, Headers),
    etap:is(Deflated, false, "received body is not deflated"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_png_data(),
        "received data for the 1st png attachment is ok"
    ),
    ok.

test_get_doc_with_1st_text_att() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc1?attachments=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    TextAttJson = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"readme.txt">>]
    ),
    TextAttType = couch_util:get_nested_json_value(
        TextAttJson,
        [<<"content_type">>]
    ),
    TextAttData = couch_util:get_nested_json_value(
        TextAttJson,
        [<<"data">>]
    ),
    etap:is(
        TextAttType,
        <<"text/plain">>,
        "1st text attachment has type text/plain"
    ),
    %% check the attachment's data is the base64 encoding of the plain text
    %% and not the base64 encoding of the gziped plain text
    etap:is(
        TextAttData,
        base64:encode(test_text_data()),
        "1st text attachment data is properly base64 encoded"
    ),
    ok.

test_1st_text_att_stub() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc1?att_encoding_info=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    {TextAttJson} = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"readme.txt">>]
    ),
    TextAttLength = proplists:get_value(<<"length">>, TextAttJson),
    etap:is(
        TextAttLength,
        length(test_text_data()),
        "1st text attachment stub length matches the uncompressed length"
    ),
    TextAttEncoding = proplists:get_value(<<"encoding">>, TextAttJson),
    etap:is(
        TextAttEncoding,
        <<"gzip">>,
        "1st text attachment stub has the encoding field set to gzip"
    ),
    TextAttEncLength = proplists:get_value(<<"encoded_length">>, TextAttJson),
    etap:is(
        TextAttEncLength,
        iolist_size(zlib:gzip(test_text_data())),
        "1st text attachment stub encoded_length matches the compressed length"
    ),
    ok.

test_get_doc_with_1st_png_att() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc2?attachments=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    PngAttJson = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"icon.png">>]
    ),
    PngAttType = couch_util:get_nested_json_value(
        PngAttJson,
        [<<"content_type">>]
    ),
    PngAttData = couch_util:get_nested_json_value(
        PngAttJson,
        [<<"data">>]
    ),
    etap:is(PngAttType, <<"image/png">>, "attachment has type image/png"),
    etap:is(
        PngAttData,
        base64:encode(test_png_data()),
        "1st png attachment data is properly base64 encoded"
    ),
    ok.

test_1st_png_att_stub() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc2?att_encoding_info=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    {PngAttJson} = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"icon.png">>]
    ),
    PngAttLength = proplists:get_value(<<"length">>, PngAttJson),
    etap:is(
        PngAttLength,
        length(test_png_data()),
        "1st png attachment stub length matches the uncompressed length"
    ),
    PngEncoding = proplists:get_value(<<"encoding">>, PngAttJson),
    etap:is(
        PngEncoding,
        undefined,
        "1st png attachment stub doesn't have an encoding field"
    ),
    PngEncLength = proplists:get_value(<<"encoded_length">>, PngAttJson),
    etap:is(
        PngEncLength,
        undefined,
        "1st png attachment stub doesn't have an encoded_length field"
    ),
    ok.

test_get_2nd_text_att_with_accept_encoding_gzip() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc3/readme.txt", [{"Accept-Encoding", "gzip"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, true, "received body is gziped"),
    Uncompressed = binary_to_list(zlib:gunzip(list_to_binary(Body))),
    etap:is(
        Uncompressed,
        test_text_data(),
        "received data for the 2nd text attachment is ok"
    ),
    ok.

test_get_2nd_text_att_without_accept_encoding_header() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc3/readme.txt", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_text_data(),
        "received data for the 2nd text attachment is ok"
    ),
    ok.

test_get_2nd_png_att_without_accept_encoding_header() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc4/icon.png", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_png_data(),
        "received data for the 2nd png attachment is ok"
    ),
    ok.

test_get_2nd_png_att_with_accept_encoding_gzip() ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc4/icon.png", [{"Accept-Encoding", "gzip"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        Body,
        test_png_data(),
        "received data for the 2nd png attachment is ok"
    ),
    ok.

test_get_doc_with_2nd_text_att() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc3?attachments=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    TextAttJson = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"readme.txt">>]
    ),
    TextAttType = couch_util:get_nested_json_value(
        TextAttJson,
        [<<"content_type">>]
    ),
    TextAttData = couch_util:get_nested_json_value(
        TextAttJson,
        [<<"data">>]
    ),
    etap:is(TextAttType, <<"text/plain">>, "attachment has type text/plain"),
    %% check the attachment's data is the base64 encoding of the plain text
    %% and not the base64 encoding of the gziped plain text
    etap:is(
        TextAttData,
        base64:encode(test_text_data()),
        "2nd text attachment data is properly base64 encoded"
    ),
    ok.

test_2nd_text_att_stub() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc3?att_encoding_info=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    {TextAttJson} = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"readme.txt">>]
    ),
    TextAttLength = proplists:get_value(<<"length">>, TextAttJson),
    etap:is(
        TextAttLength,
        length(test_text_data()),
        "2nd text attachment stub length matches the uncompressed length"
    ),
    TextAttEncoding = proplists:get_value(<<"encoding">>, TextAttJson),
    etap:is(
        TextAttEncoding,
        <<"gzip">>,
        "2nd text attachment stub has the encoding field set to gzip"
    ),
    TextAttEncLength = proplists:get_value(<<"encoded_length">>, TextAttJson),
    etap:is(
        TextAttEncLength,
        iolist_size(zlib:gzip(test_text_data())),
        "2nd text attachment stub encoded_length matches the compressed length"
    ),
    ok.

test_get_doc_with_2nd_png_att() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc4?attachments=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    PngAttJson = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"icon.png">>]
    ),
    PngAttType = couch_util:get_nested_json_value(
        PngAttJson,
        [<<"content_type">>]
    ),
    PngAttData = couch_util:get_nested_json_value(
        PngAttJson,
        [<<"data">>]
    ),
    etap:is(PngAttType, <<"image/png">>, "attachment has type image/png"),
    etap:is(
        PngAttData,
        base64:encode(test_png_data()),
        "2nd png attachment data is properly base64 encoded"
    ),
    ok.

test_2nd_png_att_stub() ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {db_url() ++ "/testdoc4?att_encoding_info=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    {PngAttJson} = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, <<"icon.png">>]
    ),
    PngAttLength = proplists:get_value(<<"length">>, PngAttJson),
    etap:is(
        PngAttLength,
        length(test_png_data()),
        "2nd png attachment stub length matches the uncompressed length"
    ),
    PngEncoding = proplists:get_value(<<"encoding">>, PngAttJson),
    etap:is(
        PngEncoding,
        undefined,
        "2nd png attachment stub doesn't have an encoding field"
    ),
    PngEncLength = proplists:get_value(<<"encoded_length">>, PngAttJson),
    etap:is(
        PngEncLength,
        undefined,
        "2nd png attachment stub doesn't have an encoded_length field"
    ),
    ok.

test_already_compressed_att(DocUri, AttName) ->
    test_get_already_compressed_att_with_accept_gzip(DocUri, AttName),
    test_get_already_compressed_att_without_accept(DocUri, AttName),
    test_get_already_compressed_att_stub(DocUri, AttName).

test_get_already_compressed_att_with_accept_gzip(DocUri, AttName) ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {DocUri ++ "/" ++ AttName, [{"Accept-Encoding", "gzip"}]},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, true, "received body is gziped"),
    etap:is(
        iolist_to_binary(Body),
        iolist_to_binary(zlib:gzip(test_text_data())),
        "received data for the already compressed attachment is ok"
    ),
    ok.

test_get_already_compressed_att_without_accept(DocUri, AttName) ->
    {ok, {{_, Code, _}, Headers, Body}} = http:request(
        get,
        {DocUri ++ "/" ++ AttName, []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Gziped = lists:member({"content-encoding", "gzip"}, Headers),
    etap:is(Gziped, false, "received body is not gziped"),
    etap:is(
        iolist_to_binary(Body),
        iolist_to_binary(test_text_data()),
        "received data for the already compressed attachment is ok"
    ),
    ok.

test_get_already_compressed_att_stub(DocUri, AttName) ->
    {ok, {{_, Code, _}, _Headers, Body}} = http:request(
        get,
        {DocUri ++ "?att_encoding_info=true", []},
        [],
        [{sync, true}]),
    etap:is(Code, 200, "HTTP response code is 200"),
    Json = couch_util:json_decode(Body),
    {AttJson} = couch_util:get_nested_json_value(
        Json,
        [<<"_attachments">>, iolist_to_binary(AttName)]
    ),
    AttLength = proplists:get_value(<<"length">>, AttJson),
    etap:is(
        AttLength,
        iolist_size((zlib:gzip(test_text_data()))),
        "Already compressed attachment stub length matches the "
        "compressed length"
    ),
    Encoding = proplists:get_value(<<"encoding">>, AttJson),
    etap:is(
        Encoding,
        <<"gzip">>,
        "Already compressed attachment stub has the encoding field set to gzip"
    ),
    EncLength = proplists:get_value(<<"encoded_length">>, AttJson),
    etap:is(
        EncLength,
        AttLength,
        "Already compressed attachment stub encoded_length matches the "
        "length field value"
    ),
    ok.

test_create_already_compressed_att_with_invalid_content_encoding(
    DocUri, AttName, AttData, Encoding) ->
    {ok, {{_, Code, _}, _Headers, _Body}} = http:request(
        put,
        {DocUri ++ "/" ++ AttName, [{"Content-Encoding", Encoding}],
        "text/plain", AttData},
        [],
        [{sync, true}]),
    etap:is(
        Code,
        415,
        "Couldn't create an already compressed attachment using the "
        "unsupported encoding '" ++ Encoding ++ "'"
    ),
    ok.

test_png_data() ->
    {ok, Data} = file:read_file(
        test_util:source_file("share/www/image/logo.png")
    ),
    binary_to_list(Data).

test_text_data() ->
    {ok, Data} = file:read_file(
        test_util:source_file("README")
    ),
    binary_to_list(Data).
