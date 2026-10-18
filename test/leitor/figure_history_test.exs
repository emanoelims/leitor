defmodule Leitor.FigureHistoryTest do
  use Leitor.DataCase

  import Leitor.AccountsFixtures

  alias Leitor.Figures.Artifacts

  test "restoring accepted ancestors preserves ownership and excludes unrelated work" do
    scope = user_scope_fixture()
    other = user_scope_fixture()
    first = ready(scope)
    second = ready(scope, first.id)
    third = ready(scope, second.id)
    unrelated = ready(scope)
    foreign = ready(other)
    assert Enum.map(Artifacts.history(scope, third.id), & &1.id) == [third.id, second.id, first.id]
    assert Artifacts.history(other, third.id) == []
    assert Artifacts.history(scope, "bad") == []
    assert {:ok, %{artifact_id: id}} = Artifacts.restore_reference(scope, third.id, first.id)
    assert id == first.id
    assert {:ok, %{artifact_id: restored}} = Artifacts.restore_reference(scope, first.id, third.id)
    assert restored == third.id

    for target <- [unrelated.id, foreign.id, Ecto.UUID.generate(), "bad"] do
      assert {:error, :invalid_revision} = Artifacts.restore_reference(scope, third.id, target)
    end

    assert Artifacts.get_ready(scope, third.id).parent_id == second.id
    refute Map.has_key?(hd(Artifacts.history(scope, third.id)), :bundle)
  end

  test "foreign or draft parents cannot establish a lineage" do
    scope = user_scope_fixture()
    foreign = ready(user_scope_fixture())
    assert {:error, changeset} = Artifacts.store(scope, Map.put(attrs(), :parent_id, foreign.id))
    assert errors_on(changeset).parent_id != []
    {:ok, draft} = Artifacts.store(scope, %{attrs() | status: "draft"})
    assert {:error, _} = Artifacts.store(scope, Map.put(attrs(), :parent_id, draft.id))
  end

  defp ready(scope, parent \\ nil) do
    {:ok, artifact} = Artifacts.store(scope, Map.put(attrs(), :parent_id, parent))
    artifact
  end

  defp attrs,
    do: %{
      title: "Mechanism",
      caption: "Accepted figure",
      model: "model",
      source: %{},
      report: %{execution: %{ok: true}},
      status: "ready",
      bundle: "bundle",
      style: "svg{}",
      preview: "png"
    }
end
