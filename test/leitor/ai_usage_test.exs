defmodule Leitor.AIUsageTest do
  use Leitor.DataCase

  import Leitor.AccountsFixtures

  alias Leitor.AI
  alias Leitor.AI.Usage

  test "usage rejects missing, negative and inconsistent counters" do
    assert {:error, _} = Usage.new(%{})
    assert {:error, _} = Usage.new(%{input_tokens: -1, output_tokens: 2})

    assert {:error, _} =
             Usage.new(%{input_tokens: 10, output_tokens: 2, cache_read_tokens: 20, input_includes_cached: true})

    assert {:error, _} = Usage.new(%{input_tokens: 1, output_tokens: 2, billing_usage_complete: false})
  end

  test "pricing counts cache separately and never double bills reasoning" do
    {:ok, usage} = Usage.new(%{input_tokens: 100, output_tokens: 20, cache_read_tokens: 1000, cache_write_tokens: 50})
    assert Usage.estimate(usage, "anthropic:claude-opus-5-5") == 1400

    {:ok, included} =
      Usage.new(%{
        input_tokens: 1150,
        output_tokens: 20,
        cache_read_tokens: 1000,
        cache_write_tokens: 50,
        input_includes_cached: true
      })

    assert Usage.estimate(included, "anthropic:claude-opus-5-5") == 1400
    assert Usage.estimate(usage, "unknown") == nil
    assert Usage.estimate(usage, "anthropic:claude-sonnet-5-5") == 700
  end

  test "Haiku pricing uses the complete prompt length at the long-context boundary" do
    {:ok, short} = Usage.new(%{input_tokens: 100_000, output_tokens: 100})
    {:ok, long} = Usage.new(%{input_tokens: 100_000, output_tokens: 100, cache_read_tokens: 1})
    assert Usage.estimate(short, AI.shared_model()) == 10_050
    assert Usage.estimate(long, AI.shared_model()) == 50_251
  end

  test "recording and finishing are scoped, cumulative, and preserve missing measurements" do
    scope = user_scope_fixture()
    other = user_scope_fixture()
    {:ok, client} = AI.prepare(scope, :read)
    options = AI.execution_options(scope, client)
    options[:usage_callback].(%{input_tokens: 1000, output_tokens: 100})
    options[:usage_callback].(%{})
    assert_raise Ecto.NoResultsError, fn -> AI.record_usage(other, client.lease_id, %{}) end
    :ok = AI.finish(scope, client.lease_id, :cancelled)
    :ok = AI.finish(scope, client.lease_id)

    assert [%{outcome: "cancelled", measured_calls: 1, unmeasured_calls: 1, estimated_cost_micros: 150}] =
             AI.recent_attempts(scope)

    assert AI.recent_attempts(other) == []
    assert %{attempts: 1, active: 0, input_tokens: 1000, output_tokens: 100, cost: 150} = AI.activity(scope)
    assert %{attempts: 0, cost: 0} = AI.activity(other)
  end
end
