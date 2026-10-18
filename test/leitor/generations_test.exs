defmodule Leitor.GenerationsTest do
  use Leitor.DataCase, async: false

  import Leitor.AccountsFixtures
  import Leitor.FigureFixtures

  alias Leitor.AI.Reservation
  alias Leitor.Figures.Artifacts
  alias Leitor.Generations
  alias Leitor.Generations.Generation

  setup do
    previous = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageGate)
    Application.put_env(:leitor, :language_test_owner, self())

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :language_adapter, previous),
        else: Application.delete_env(:leitor, :language_adapter)

      Application.delete_env(:leitor, :language_test_owner)
    end)

    %{scope: user_scope_fixture()}
  end

  defp attrs do
    %{
      client_id: "durable",
      request: %{prompt: "A connected mechanism", title: "Mechanism", context: "", draft_body: "Keep my text."}
    }
  end

  test "explicitly empty optional context remains a valid request through provider completion", %{scope: scope} do
    request = attrs() |> Map.fetch!(:request) |> Map.merge(%{context: nil, draft_body: nil})
    assert {:ok, job} = Generations.start(scope, nil, %{attrs() | request: request})
    assert job.request.context == ""
    assert job.request.draft_body == ""
    assert_receive {:language_started, task}
    send(task, {:complete, {:ok, figure_response("An empty draft is valid.")}})
    assert {:ok, _} = Generations.await(scope, job.id)
  end

  test "a completed attempt is recoverable without another reservation or provider call", %{scope: scope} do
    assert {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    usage = Leitor.AI.usage(scope)
    send(task, {:complete, {:ok, figure_response("Done.")}})
    assert {:ok, %{"markdown" => markdown}} = Generations.await(scope, job.id)
    assert markdown =~ "Done."
    assert Generations.latest(scope, nil).id == job.id
    assert Generations.latest(scope, nil).request.draft_body == "Keep my text."
    assert Leitor.AI.usage(scope) == usage
    refute_receive {:language_started, _}
  end

  test "only the owning account can fetch, stop or dismiss a generation", %{scope: scope} do
    {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    monitor = Process.monitor(task)
    other = user_scope_fixture()
    assert Generations.latest(other, nil) == nil
    assert_raise Ecto.NoResultsError, fn -> Generations.get!(other, job.id) end
    assert_raise Ecto.NoResultsError, fn -> Generations.cancel(other, job.id) end
    assert_raise Ecto.NoResultsError, fn -> Generations.dismiss(other, job.id) end
    assert :ok = Generations.cancel(scope, job.id)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}
    assert Generations.get!(scope, job.id).status == "failed"
    assert Repo.get!(Reservation, job.lease_id).outcome == "cancelled"
    assert :ok = Generations.dismiss(scope, job.id)
    assert Generations.latest(scope, nil) == nil
  end

  test "expired attempts release capacity and stop their provider process", %{scope: scope} do
    {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    monitor = Process.monitor(task)

    job
    |> Ecto.Changeset.change(expires_at: DateTime.utc_now() |> DateTime.shift(second: -1) |> DateTime.truncate(:second))
    |> Repo.update!()

    assert Generations.latest(scope, nil).error == "figure_budget_exceeded"
    assert_receive {:DOWN, ^monitor, :process, ^task, _}
  end

  test "malformed snapshots and foreign figure revisions never reserve AI credits", %{scope: scope} do
    assert {:error, %Ecto.Changeset{}} = Generations.start(scope, nil, put_in(attrs(), [:request, :prompt], " "))

    revision_request =
      update_in(
        attrs(),
        [:request],
        &Map.merge(&1, %{base_revision_id: Ecto.UUID.generate(), replace_from: 0, replace_to: 1})
      )

    assert {:error, :invalid_input} = Generations.start(scope, nil, revision_request)

    assert Leitor.AI.usage(scope).used == 0
    assert Repo.all(Generation) == []
    refute_receive {:language_started, _}
  end

  test "busy requests wait without charges, dispatch once and remain recoverable", %{scope: scope} do
    {:ok, running} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, first_task}
    assert {:ok, queued} = Generations.start(scope, nil, %{attrs() | client_id: "waiting"})
    assert queued.status == "queued"
    assert queued.lease_id == nil
    assert Leitor.AI.usage(scope).used == 4
    assert Generations.queued_count(scope) == 1
    assert Generations.latest(scope, nil).id == queued.id
    assert {:error, :busy} = Generations.start(scope, nil, %{attrs() | client_id: "excess"})
    assert :ok = Generations.dispatch_queued()
    refute_receive {:language_started, _}
    send(first_task, {:complete, {:ok, figure_response("First")}})
    assert {:ok, _} = Generations.await(scope, running.id)
    assert :ok = Generations.dispatch_queued()
    assert_receive {:language_started, second_task}
    assert Generations.get!(scope, queued.id).status == "running"
    assert Leitor.AI.usage(scope).used == 8
    assert Generations.queued_count(scope) == 0
    assert :ok = Generations.dispatch_queued()
    refute_receive {:language_started, _}
    send(second_task, {:complete, {:ok, figure_response("Second")}})
    assert {:ok, %{"markdown" => body}} = Generations.await(scope, queued.id)
    assert body =~ "Second"
  end

  test "waiting requests can be canceled and expire without a reservation", %{scope: scope} do
    {:ok, running} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, first_task}
    {:ok, queued} = Generations.start(scope, nil, %{attrs() | client_id: "cancel-waiting"})
    assert :ok = Generations.cancel(scope, queued.id)
    assert Generations.get!(scope, queued.id).status == "failed"
    assert Leitor.AI.usage(scope).used == 4
    {:ok, expiring} = Generations.start(scope, nil, %{attrs() | client_id: "expire-waiting"})
    Repo.update!(Ecto.Changeset.change(expiring, expires_at: DateTime.shift(DateTime.utc_now(:second), second: -1)))
    Generations.dispatch_queued()
    assert Generations.get!(scope, expiring.id).status == "failed"
    assert Leitor.AI.usage(scope).used == 4
    send(first_task, {:complete, {:ok, figure_response("Done")}})
    assert {:ok, _} = Generations.await(scope, running.id)
    Generations.dispatch_queued()
    refute_receive {:language_started, _}
  end

  test "a quota exhausted while waiting blocks dispatch without a provider request", %{scope: scope} do
    {:ok, running} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, first_task}
    {:ok, queued} = Generations.start(scope, nil, %{attrs() | client_id: "wait-for-quota"})
    bucket = Repo.get!(Leitor.AI.Bucket, "user:#{scope.user.id}:#{Date.utc_today()}")
    Repo.update!(Ecto.Changeset.change(bucket, used: Leitor.AI.policy().daily_limit))
    send(first_task, {:complete, {:ok, figure_response("Done")}})
    assert {:ok, _} = Generations.await(scope, running.id)
    Generations.dispatch_queued()
    assert {:error, :quota_exceeded} = Generations.await(scope, queued.id)
    assert Generations.get!(scope, queued.id).lease_id == nil
    refute_receive {:language_started, _}
  end

  test "canceling a finished job preserves its result and measured outcome", %{scope: scope} do
    {:ok, job} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, task}
    send(task, {:complete, {:ok, figure_response("Keep this result")}})
    assert {:ok, result} = Generations.await(scope, job.id)
    assert :ok = Generations.cancel(scope, job.id)
    assert {:ok, ^result} = Generations.await(scope, job.id)
    assert Repo.get!(Reservation, job.lease_id).outcome == "completed"
  end

  test "an unchanged retry keeps its private checkpoint when it joins the queue", %{scope: scope} do
    {:ok, previous} = Generations.start(scope, nil, attrs())
    assert_receive {:language_started, first_task}

    {:ok, checkpoint} =
      Artifacts.store(scope, %{
        title: "Checkpoint",
        caption: "Unfinished",
        model: "model",
        source: %{},
        report: %{},
        status: "draft"
      })

    Generations.checkpoint(scope, previous.id, checkpoint.id)
    send(first_task, {:complete, {:error, :figure_budget_exceeded}})
    assert {:error, :figure_budget_exceeded} = Generations.await(scope, previous.id)

    busy_attrs = put_in(attrs(), [:request, :prompt], "Another mechanism")
    {:ok, busy} = Generations.start(scope, nil, busy_attrs)
    assert_receive {:language_started, second_task}
    # The original editor, rather than an unrelated new-page attempt, owns the retry.
    Generations.dismiss(scope, busy.id)
    assert {:ok, waiting} = Generations.start(scope, nil, attrs())
    assert waiting.status == "queued"
    assert waiting.revision_id == checkpoint.id
    Generations.cancel(scope, waiting.id)
    send(second_task, {:complete, {:ok, figure_response("Done")}})
    assert {:ok, _} = Generations.await(scope, busy.id)
  end
end
