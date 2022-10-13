defmodule Membrane.RTMP.DefaultMessageValidator do
  @moduledoc """
  A default validator for the `Membrane.RTMP.SourceBin`, that allows all incoming streams.
  """
  use Membrane.RTMP.MessageValidator
end
