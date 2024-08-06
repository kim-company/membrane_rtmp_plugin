defmodule Membrane.RTMP.SourceBin do
  @moduledoc """
  Bin responsible for demuxing and parsing an RTMP stream.

  Outputs single audio and video which are ready for further processing with Membrane Elements.
  At this moment only AAC and H264 codecs are supported.

  The bin can be used in the following two scenarios:
  * by providing the URL on which the client is expected to connect - note, that if the client doesn't
  connect on this URL, the bin won't complete its setup
  * by spawning `Membrane.RTMP.Server`, receiving client reference after client connects on a given `app` and `stream_key`
  and passing the client reference to the `#{inspect(__MODULE__)}`.
  """
  use Membrane.Bin

  alias Membrane.{AAC, H264, RTMP}

  def_output_pad :video,
    accepted_format: H264,
    availability: :on_request

  def_output_pad :audio,
    accepted_format: AAC,
    availability: :on_request

  def_options client_ref: [
                default: nil,
                spec: pid(),
                description: """
                A pid of a process acting as a client reference.
                Can be gained with the use of `Membrane.RTMP.Server`.
                """
              ],
              url: [
                default: nil,
                spec: String.t(),
                description: """
                An URL on which the client is expected to connect, for example:
                rtmp://127.0.0.1:1935/app/stream_key
                """
              ]

  @impl true
  def handle_init(_ctx, %__MODULE__{} = opts) do
    spec = [
      child(:src, %RTMP.Source{
        client_ref: opts.client_ref,
        url: opts.url
      })
      |> child(:demuxer, Membrane.FLV.Demuxer)
    ]

    state = %{
      demuxer_audio_pad_ref: nil,
      demuxer_video_pad_ref: nil
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:audio, _ref) = pad, _ctx, state) do
    spec =
      if state.demuxer_audio_pad_ref != nil do
        [
          get_child(:demuxer)
          |> via_out(state.demuxer_audio_pad_ref)
          |> child(:audio_parser, %Membrane.AAC.Parser{
            out_encapsulation: :none
          })
          |> bin_output(pad)
        ]
      else
        [
          child(:funnel_audio, Membrane.Funnel)
          |> bin_output(pad)
        ]
      end

    {[spec: spec], state}
  end

  def handle_pad_added(Pad.ref(:video, _ref) = pad, _ctx, state) do
    spec =
      if state.demuxer_video_pad_ref != nil do
        [
          get_child(:demuxer)
          |> via_out(state.demuxer_video_pad_ref)
          |> child(:video_parser, Membrane.H264.Parser)
          |> bin_output(pad)
        ]
      else
        [
          child(:funnel_video, Membrane.Funnel)
          |> bin_output(pad)
        ]
      end

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification({:new_stream, pad_ref, :AAC}, :demuxer, ctx, state) do
    audio_pad_ref = get_pad(:audio, ctx)

    if audio_pad_ref != nil do
      {[
         spec: [
           get_child(:demuxer)
           |> via_out(pad_ref)
           |> child(:audio_parser, %Membrane.AAC.Parser{
             out_encapsulation: :none
           })
           |> get_child(:funnel_audio)
         ]
       ], state}
    else
      {[], %{state | demuxer_audio_pad_ref: pad_ref}}
    end
  end

  def handle_child_notification({:new_stream, pad_ref, :H264}, :demuxer, ctx, state) do
    video_pad_ref = get_pad(:video, ctx)

    if video_pad_ref != nil do
      {[
         spec: [
           get_child(:demuxer)
           |> via_out(pad_ref)
           |> child(:video_parser, Membrane.H264.Parser)
           |> get_child(:funnel_video)
         ]
       ], state}
    else
      {[], %{state | demuxer_video_pad_ref: pad_ref}}
    end
  end

  def handle_child_notification(
        {type, _socket, _pid} = notification,
        :src,
        _ctx,
        state
      )
      when type in [:socket_control_needed, :ssl_socket_control_needed] do
    {[notify_parent: notification], state}
  end

  def handle_child_notification(
        {type, _stage, _reason} = notification,
        :src,
        _ctx,
        state
      )
      when type in [:stream_validation_success, :stream_validation_error] do
    {[notify_parent: notification], state}
  end

  def handle_child_notification(:unexpected_socket_closed, :src, _ctx, state) do
    {[notify_parent: :unexpected_socket_close], state}
  end

  @doc """
  Passes the control of the socket to the `source`.

  To succeed, the executing process must be in control of the socket, otherwise `{:error, :not_owner}` is returned.
  """
  @spec pass_control(:gen_tcp.socket(), pid()) :: :ok | {:error, atom()}
  def pass_control(socket, source) do
    :gen_tcp.controlling_process(socket, source)
  end

  @doc """
  Passes the control of the ssl socket to the `source`.

  To succeed, the executing process must be in control of the socket, otherwise `{:error, :not_owner}` is returned.
  """
  @spec secure_pass_control(:ssl.sslsocket(), pid()) :: :ok | {:error, any()}
  def secure_pass_control(socket, source) do
    :ssl.controlling_process(socket, source)
  end

  defp get_pad(name, ctx) do
    ctx.pads
    |> Map.keys()
    |> Enum.find(fn pad_ref -> Pad.name_by_ref(pad_ref) == name end)
  end
end
