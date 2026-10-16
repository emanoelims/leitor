defmodule LeitorWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LeitorWeb.CoreComponents

  test "validation remains associated with custom controls and existing help text" do
    for type <- ["text", "textarea", "select", "checkbox"] do
      html =
        render_component(&CoreComponents.input/1,
          id: "answer",
          name: "answer",
          value: "",
          label: "Answer",
          type: type,
          options: [{"One", "one"}],
          class: "custom-control",
          errors: ["Choose an answer"],
          "aria-describedby": "answer-help"
        )

      document = LazyHTML.from_fragment(html)
      control = LazyHTML.query(document, "#answer")
      assert LazyHTML.attribute(control, "aria-invalid") == ["true"]
      assert LazyHTML.attribute(control, "aria-describedby") == ["answer-help answer-errors"]
      assert document |> LazyHTML.query("#answer-errors") |> LazyHTML.text() |> String.trim() == "Choose an answer"
    end
  end

  test "valid controls retain their help text without an obsolete error reference" do
    html =
      render_component(&CoreComponents.input/1,
        id: "answer",
        name: "answer",
        value: "A thought",
        label: "Answer",
        errors: [],
        "aria-describedby": "answer-help"
      )

    document = LazyHTML.from_fragment(html)
    control = LazyHTML.query(document, "#answer")
    assert LazyHTML.attribute(control, "aria-describedby") == ["answer-help"]
    refute "true" in LazyHTML.attribute(control, "aria-invalid")
    assert LazyHTML.text(LazyHTML.query(document, "#answer-errors")) == ""
  end
end
