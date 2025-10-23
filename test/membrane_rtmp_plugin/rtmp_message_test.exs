defmodule Membrane.RTMP.MessageTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Message

  describe "chunk_payload/4" do
    setup do
      payload = <<0, 1, 2, 3, 4, 5, 6, 7, 8>>
      chunk_size = 4

      %{payload: payload, chunk_size: chunk_size}
    end

    test "uses 1-byte chunk basic header for chunk stream ids below 64", %{
      payload: payload,
      chunk_size: chunk_size
    } do
      chunk_stream_id = 10

      iodata = Message.chunk_payload(payload, chunk_stream_id, chunk_size)

      expected_separator = <<0b11::2, chunk_stream_id::6>>

      assert IO.iodata_to_binary(iodata) ==
               <<0, 1, 2, 3>> <>
                 expected_separator <>
                 <<4, 5, 6, 7>> <>
                 expected_separator <>
                 <<8>>
    end

    test "uses 2-byte chunk basic header for chunk stream ids between 64 and 319", %{
      payload: payload,
      chunk_size: chunk_size
    } do
      chunk_stream_id = 200

      iodata = Message.chunk_payload(payload, chunk_stream_id, chunk_size)

      expected_separator = <<0b11::2, 0::6, chunk_stream_id - 64::8>>

      assert IO.iodata_to_binary(iodata) ==
               <<0, 1, 2, 3>> <>
                 expected_separator <>
                 <<4, 5, 6, 7>> <>
                 expected_separator <>
                 <<8>>
    end

    test "uses 3-byte chunk basic header for chunk stream ids greater than 319", %{
      payload: payload,
      chunk_size: chunk_size
    } do
      chunk_stream_id = 500
      id_minus_64 = chunk_stream_id - 64
      low_byte = rem(id_minus_64, 256)
      high_byte = div(id_minus_64, 256)

      iodata = Message.chunk_payload(payload, chunk_stream_id, chunk_size)

      expected_separator = <<0b11::2, 1::6, low_byte::8, high_byte::8>>

      assert IO.iodata_to_binary(iodata) ==
               <<0, 1, 2, 3>> <>
                 expected_separator <>
                 <<4, 5, 6, 7>> <>
                 expected_separator <>
                 <<8>>
    end
  end
end
