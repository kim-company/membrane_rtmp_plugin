defmodule Membrane.RTMPServer.TCPOptionsTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMPServer

  test "applies TCP options to accepted client sockets" do
    socket = connect_to_server(tcp_options: [keepalive: true])

    assert :inet.getopts(socket, [:keepalive]) == {:ok, [keepalive: true]}
  end

  test "leaves keepalive disabled by default" do
    socket = connect_to_server([])

    assert :inet.getopts(socket, [:keepalive]) == {:ok, [keepalive: false]}
  end

  defp connect_to_server(options) do
    server =
      start_supervised!(
        {RTMPServer,
         Keyword.merge(
           [
             port: 0,
             handle_new_client: fn _client_ref, _app, _stream_key ->
               flunk("RTMP handshake should not be reached")
             end
           ],
           options
         )}
      )

    port = RTMPServer.get_port(server)
    {:ok, listener} = :sys.get_state(server).listener
    {:ok, client} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    on_exit(fn -> :gen_tcp.close(client) end)
    {:ok, client_address} = :inet.sockname(client)

    accepted_socket(client_address, listener, 100)
  end

  defp accepted_socket(_client_address, _listener, 0) do
    flunk("accepted client socket was not transferred to its handler")
  end

  defp accepted_socket(client_address, listener, attempts) do
    socket =
      Enum.find(Port.list(), fn socket ->
        :inet.peername(socket) == {:ok, client_address} and
          match?({:connected, owner} when owner != listener, Port.info(socket, :connected))
      end)

    if socket do
      socket
    else
      Process.sleep(10)
      accepted_socket(client_address, listener, attempts - 1)
    end
  end
end
