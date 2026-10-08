defmodule Leitor.Accounts do
  @moduledoc """
  Registers users, validates credentials, and manages authentication tokens.

  `Leitor.Accounts.User` owns account data and changesets. Web session handling
  lives in `LeitorWeb.UserAuth`. Token expiry and revocation are enforced here
  and in `Leitor.Accounts.UserToken`.
  """

  import Ecto.Query, warn: false

  alias Leitor.Accounts.User
  alias Leitor.Accounts.UserNotifier
  alias Leitor.Accounts.UserToken
  alias Leitor.Repo

  @doc """
  Finds a user by email, returning `nil` when no account matches.
  """
  @spec get_user_by_email(User.email()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Finds a user whose email and password match.

  Returns `nil` for unknown accounts or invalid passwords. Verification performs
  work for missing accounts to reduce timing differences.
  """
  @spec get_user_by_email_and_password(User.email(), User.password()) :: User.t() | nil
  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Finds a user by UUID.

  Raises `Ecto.NoResultsError` when no account matches. Malformed IDs may raise
  `Ecto.Query.CastError`.
  """
  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Registers an unconfirmed account with a validated, unique email.

  Returns `{:ok, user}` or `{:error, changeset}`. Registration does not set a
  password or send an email; login instructions are delivered separately.

  ## Examples

      iex> {:ok, user} = Leitor.Accounts.register_user(%{email: "registration@example.com"})
      iex> {user.email, user.confirmed_at, user.hashed_password}
      {"registration@example.com", nil, nil}

      iex> {:error, changeset} = Leitor.Accounts.register_user(%{})
      iex> Keyword.has_key?(changeset.errors, :email)
      true
  """
  @spec register_user(User.attrs()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t(User.t())}
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(User.t() | nil, integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.shift(DateTime.utc_now(), minute: minutes))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Builds an email changeset without persisting it.

  See `Leitor.Accounts.User.email_changeset/3` for validation options.
  """
  @spec change_user_email(User.t(), User.attrs(), User.email_options()) :: Ecto.Changeset.t(User.t())
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(User.t(), UserToken.email_token()) :: {:ok, User.t()} | {:error, :transaction_aborted}
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Builds a password changeset without persisting it.

  See `Leitor.Accounts.User.password_changeset/3` for validation and hashing options.

  ## Examples

      iex> changeset = Leitor.Accounts.change_user_password(%Leitor.Accounts.User{}, %{password: "short"}, hash_password: false)
      iex> changeset.valid?
      false
  """
  @spec change_user_password(User.t(), User.attrs(), User.password_options()) :: Ecto.Changeset.t(User.t())
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Validates and updates a password, revoking all of the user's stored tokens.

  Returns `{:ok, {user, expired_tokens}}` after a successful transaction, or
  `{:error, changeset}` when validation fails. The returned user has no plaintext
  password. Callers can disconnect existing LiveView sessions using the revoked
  tokens and `LeitorWeb.UserAuth.disconnect_sessions/1`.
  """
  @spec update_user_password(User.t(), User.attrs()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, Ecto.Changeset.t(User.t())}
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(User.t()) :: UserToken.session_token()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(UserToken.session_token()) :: {User.t(), DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  @spec get_user_by_magic_link_token(UserToken.email_token()) :: User.t() | nil
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  @spec login_user_by_magic_link(UserToken.email_token()) ::
          {:ok, {User.t(), [UserToken.t()]}} | {:error, :not_found | Ecto.Changeset.t(User.t())}
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Stores an email-change token and delivers instructions to the user's new email.

  `current_email` identifies the previous address. The URL callback receives
  the encoded token and must return an absolute URL. Returns `{:ok, email}` or
  the mailer's `{:error, reason}`. The token is stored before delivery, so a
  delivery error does not roll back its insertion.
  """
  @spec deliver_user_update_email_instructions(User.t(), User.email(), (UserToken.email_token() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  @spec deliver_login_instructions(User.t(), (UserToken.email_token() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_login_instructions(%User{} = user, magic_link_url_fun) when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(UserToken.session_token()) :: :ok
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
