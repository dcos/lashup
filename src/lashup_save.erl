%% Borrowed from: https://github.com/basho/riak_ensemble/blob/develop/src/riak_ensemble_save.erl
%% -------------------------------------------------------------------
%%
%% Copyright (c) 2013 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc
%% Provide a safe method of saving data to disk along with a checksum
%% that is verified on read. Additionally, four replicas of the data
%% are stored across two files for greater redundancy/durability.

-module(lashup_save).
-export([write/2, read/1]).

%%===================================================================

-spec write(file:filename(), binary()) -> ok | {error, term()}.
write(File, Data) ->
  CRC = erlang:crc32(Data),
  Size = byte_size(Data),
  Meta = <<CRC:32/integer, Size:32/integer>>,
  Out = [Meta, Data,  %% copy 1
    Data, Meta], %% copy 2
  ok = filelib:ensure_dir(File),
  try
    _ = Out,
    ok = lashup_utils:replace_file(File, Out),
    ok = lashup_utils:replace_file(File ++ ".backup", Out),
    ok
  catch
    _:Err ->
      {error, Err}
  end.

-spec read(file:filename()) -> {ok, binary()} | not_found.
read(File) ->
  case do_read(File) of
    not_found ->
      do_read(File ++ ".backup");
    Result ->
      Result
  end.

%%===================================================================

-spec do_read(file:filename()) -> {ok, binary()} | not_found.
do_read(File) ->
  case lashup_utils:read_file(File) of
    {ok, Binary} ->
      safe_read(Binary);
    {error, _} ->
      not_found
  end.

-spec safe_read(binary()) -> {ok, binary()} | not_found.
safe_read(<<CRC:32/integer, Size:32/integer, Data:Size/binary, Rest/binary>>) ->
  case erlang:crc32(Data) of
    CRC ->
      {ok, Data};
    _ ->
      safe_read_backup(Rest)
  end;
safe_read(Binary) ->
  safe_read_backup(Binary).

-spec safe_read_backup(binary()) -> {ok, binary()} | not_found.
safe_read_backup(Binary) when byte_size(Binary) =< 8 ->
  not_found;
safe_read_backup(Binary) ->
  BinSize = byte_size(Binary),
  Skip = BinSize - 8,
  <<_:Skip/binary, CRC:32/integer, Size:32/integer>> = Binary,
  Skip2 = Skip - Size,
  case Binary of
    <<_:Skip2/binary, Data:Size/binary, _:8/binary>> ->
      case erlang:crc32(Data) of
        CRC ->
          {ok, Data};
        _ ->
          not_found
      end;
    _ ->
      not_found
  end.
