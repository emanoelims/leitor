defmodule LeitorWeb.Locale do
  @moduledoc "Sets the account's Gettext locale independently for HTTP and each LiveView process."

  import Phoenix.Component, only: [assign_new: 3]
  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    conn = fetch_cookies(conn)
    locale = account_locale(conn.assigns.current_scope, conn.cookies["leitor_locale"])
    Gettext.put_locale(LeitorWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  def on_mount(:default, _params, _session, socket) do
    socket = assign_new(socket, :locale, fn -> "en" end)

    fallback =
      if Phoenix.LiveView.connected?(socket),
        do: Phoenix.LiveView.get_connect_params(socket)["locale"],
        else: socket.assigns.locale

    locale = account_locale(socket.assigns.current_scope, fallback)
    Gettext.put_locale(LeitorWeb.Gettext, locale)

    {:cont,
     socket
     |> Phoenix.Component.assign(:locale, locale)
     |> Phoenix.LiveView.push_event("locale-changed", %{locale: locale, translations: LeitorWeb.I18n.client_dictionary()})}
  end

  defp account_locale(%{user: %{preferences: %{locale: locale}}}, _fallback), do: locale
  defp account_locale(_scope, "pt_BR"), do: "pt_BR"
  defp account_locale(_scope, _fallback), do: "en"
end
