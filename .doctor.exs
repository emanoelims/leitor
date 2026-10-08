%Doctor.Config{
  # Enforce domain contracts. Phoenix callbacks, generated infrastructure, and
  # test helpers are checked by compilation, Credo, Dialyzer, and their tests.
  ignore_paths: [
    ~r{^lib/leitor_web/},
    "lib/leitor_web.ex",
    "lib/leitor/application.ex",
    "lib/leitor/repo.ex",
    "lib/leitor/mailer.ex",
    ~r{^test/support/}
  ],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 90,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 90,
  exception_moduledoc_required: true,
  struct_type_spec_required: true,
  raise: true,
  reporter: Doctor.Reporters.Summary,
  umbrella: false
}
