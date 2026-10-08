defmodule Leitor.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Leitor.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Leitor.Accounts.User

  defstruct user: nil

  @typedoc "The caller context, optionally containing a user."
  @type t() :: %__MODULE__{user: User.t() | nil}

  @doc """
  Creates a scope for the given user.

  Returns `nil` if no user is given.

  ## Examples

      iex> user = %Leitor.Accounts.User{email: "reader@example.com"}
      iex> scope = Leitor.Accounts.Scope.for_user(user)
      iex> scope.user.email
      "reader@example.com"

      iex> Leitor.Accounts.Scope.for_user(nil)
      nil
  """
  @spec for_user(User.t() | nil) :: t() | nil
  def for_user(user)

  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil
end
