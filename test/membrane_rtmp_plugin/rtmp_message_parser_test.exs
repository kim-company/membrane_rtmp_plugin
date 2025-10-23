defmodule Membrane.RTMP.MessageParserTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.{Header, MessageParser, Messages}
  require Header

  @chunk_size 4
  @body <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>

  describe "handle_packet/2 with extended chunk stream ids" do
    test "parses video message chunked with 2-byte chunk stream id" do
      chunk_stream_id = 200
      packet = build_packet(chunk_stream_id, @body)
      state = message_parser_state(@chunk_size)

      {%Header{} = header, %Messages.Video{} = message, _state} =
        MessageParser.handle_packet(packet, state)

      assert header.chunk_stream_id == chunk_stream_id
      assert message.data == @body
    end

    test "parses video message chunked with 3-byte chunk stream id" do
      chunk_stream_id = 500
      packet = build_packet(chunk_stream_id, @body)
      state = message_parser_state(@chunk_size)

      {%Header{} = header, %Messages.Video{} = message, _state} =
        MessageParser.handle_packet(packet, state)

      assert header.chunk_stream_id == chunk_stream_id
      assert message.data == @body
    end

    test "parses video message with extended timestamp for multi-byte chunk stream id" do
      chunk_stream_id = 500
      timestamp = 0x1FF_FFFF
      packet = build_packet(chunk_stream_id, @body, timestamp: timestamp)
      state = message_parser_state(@chunk_size)

      {%Header{} = header, %Messages.Video{} = message, _state} =
        MessageParser.handle_packet(packet, state)

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == timestamp
      assert header.extended_timestamp?
      assert message.data == @body
    end
  end

  defp message_parser_state(chunk_size) do
    %MessageParser{
      state_machine: :connected,
      buffer: <<>>,
      previous_headers: %{},
      chunk_size: chunk_size,
      current_tx_id: 1,
      handshake: nil
    }
  end

  defp build_packet(chunk_stream_id, body, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, 0)
    type_id = Header.type(:video_message)
    stream_id = 1

    {timestamp_field, extended_timestamp} = encode_timestamp(timestamp)
    basic_header = basic_header(0, chunk_stream_id)

    message_header =
      <<timestamp_field::binary, byte_size(body)::24, type_id::8, stream_id::little-32>>

    chunks =
      body
      |> split_chunks(@chunk_size)
      |> assemble_chunks(chunk_stream_id, timestamp, extended_timestamp != <<>>)

    IO.iodata_to_binary([basic_header, message_header, extended_timestamp, chunks])
  end

  defp assemble_chunks([first | rest], chunk_stream_id, timestamp, extended?) do
    [
      first
      | Enum.map(rest, fn chunk ->
          [
            basic_header(3, chunk_stream_id),
            maybe_extended_timestamp(timestamp, extended?),
            chunk
          ]
        end)
    ]
  end

  defp split_chunks(body, chunk_size) when byte_size(body) <= chunk_size, do: [body]

  defp split_chunks(body, chunk_size) do
    <<chunk::binary-size(chunk_size), rest::binary>> = body
    [chunk | split_chunks(rest, chunk_size)]
  end

  defp encode_timestamp(timestamp) when timestamp < 0xFFFFFF, do: {<<timestamp::24>>, <<>>}

  defp encode_timestamp(timestamp), do: {<<0xFFFFFF::24>>, <<timestamp::32>>}

  defp maybe_extended_timestamp(_timestamp, false), do: <<>>
  defp maybe_extended_timestamp(timestamp, true), do: <<timestamp::32>>

  defp basic_header(fmt, chunk_stream_id) when chunk_stream_id <= 63 do
    <<fmt::2, chunk_stream_id::6>>
  end

  defp basic_header(fmt, chunk_stream_id) when chunk_stream_id <= 319 do
    <<fmt::2, 0::6, chunk_stream_id - 64::8>>
  end

  defp basic_header(fmt, chunk_stream_id) do
    id_minus_64 = chunk_stream_id - 64
    low = rem(id_minus_64, 256)
    high = div(id_minus_64, 256)

    <<fmt::2, 1::6, low::8, high::8>>
  end
end
