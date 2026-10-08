defmodule LeitorWeb.Presence do
  @moduledoc false
  use Phoenix.Presence, otp_app: :leitor, pubsub_server: Leitor.PubSub
end
