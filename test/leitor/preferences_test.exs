defmodule Leitor.Accounts.PreferencesTest do
  use Leitor.DataCase

  import Leitor.AccountsFixtures

  alias Leitor.Accounts
  alias Leitor.Accounts.Preferences

  test "defaults preserve the existing language and model behavior" do
    assert {:ok, preferences} = Preferences.new(%{})
    assert preferences.locale == "en"
    assert preferences.ai_locale == "auto"
    assert preferences.reading_model == "default"
    assert preferences.writing_model == "default"
    assert {"English", "en"} in Preferences.languages()
    assert {"Follow the request", "auto"} in Preferences.response_languages()
    assert length(Preferences.models()) == 4
  end

  test "validates every choice at the boundary" do
    for field <- [:locale, :ai_locale, :reading_model, :writing_model], value <- ["", "unsupported"] do
      assert {:error, changeset} = Preferences.new(%{field => value})
      assert Keyword.has_key?(changeset.errors, field)
    end
  end

  test "scopes updates, preserves sessions and reads changes from another tab" do
    scope = user_scope_fixture()
    other = user_scope_fixture()
    token = Accounts.generate_user_session_token(scope.user)

    assert {:ok, user} =
             Accounts.update_preferences(scope, %{
               "locale" => "pt_BR",
               "ai_locale" => "en",
               "reading_model" => "anthropic:claude-opus-5-5",
               "writing_model" => "anthropic:claude-sonnet-5-5",
               "id" => other.user.id,
               "email" => other.user.email
             })

    assert user.id == scope.user.id
    assert user.email == scope.user.email
    assert Accounts.get_preferences(scope).locale == "pt_BR"
    assert Accounts.get_preferences(other).locale == "en"
    assert {%{id: id}, _} = Accounts.get_user_by_session_token(token)
    assert id == scope.user.id

    assert {:ok, user} = Accounts.update_preferences(scope, %{ai_locale: "pt_BR"})
    assert user.preferences.locale == "pt_BR"
    assert user.preferences.reading_model == "anthropic:claude-opus-5-5"
    assert {:error, _} = Accounts.update_preferences(scope, %{locale: "fr"})
    assert Accounts.get_preferences(scope).locale == "pt_BR"
    assert Accounts.change_preferences(scope).valid?
  end
end
