defmodule Leitor.Accounts.UserNotifierTest do
  use ExUnit.Case, async: false

  alias Leitor.Accounts.User
  alias Leitor.Accounts.UserNotifier

  test "authentication email uses the configured verified sender and retains its login link" do
    previous = Application.fetch_env!(:leitor, :mail_from)
    on_exit(fn -> Application.put_env(:leitor, :mail_from, previous) end)
    Application.put_env(:leitor, :mail_from, {"Leitor", "login@example.test"})
    user = %User{email: "reader@example.test", confirmed_at: DateTime.utc_now()}

    assert {:ok, email} = UserNotifier.deliver_login_instructions(user, "https://leitor.example.test/users/log-in/token")
    assert email.from == {"Leitor", "login@example.test"}
    assert email.to == [{"", user.email}]
    assert email.text_body =~ "https://leitor.example.test/users/log-in/token"
  end
end
