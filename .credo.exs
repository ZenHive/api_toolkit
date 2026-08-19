# Credo configuration for api_toolkit.
#
# Plugins:
#   * ExSlop     — AI-generated-code antipatterns (31 default checks)
#   * ExDNA.Credo — AST-based duplicate/clone detection
#
# TagTODO / TagFIXME stay ENABLED here for visibility (`mix credo` surfaces
# tracked debt). The CI/alias gate passes `--ignore TagTODO,TagFIXME` so
# accumulated tags never block a commit — the config is the inventory, the
# flag is the gate.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/priv/"]
      },
      plugins: [{ExSlop, []}, {ExDNA.Credo, []}],
      strict: true,
      color: true,
      checks: %{
        enabled:
          [
            #
            ## Consistency
            #
            {Credo.Check.Consistency.ExceptionNames, []},
            {Credo.Check.Consistency.LineEndings, []},
            {Credo.Check.Consistency.ParameterPatternMatching, []},
            {Credo.Check.Consistency.SpaceAroundOperators, []},
            {Credo.Check.Consistency.SpaceInParentheses, []},
            {Credo.Check.Consistency.TabsOrSpaces, []},

            #
            ## Design
            #
            # Scoped to lib/ — fully-qualified calls in test setup are clearer than
            # aliasing a module referenced once.
            {Credo.Check.Design.AliasUsage,
             [if_nested_deeper_than: 2, if_called_more_often_than: 0, files: %{excluded: [~r"/test/"]}]},
            {Credo.Check.Design.TagTODO, [exit_status: 2]},
            {Credo.Check.Design.TagFIXME, []},

            #
            ## Readability
            #
            {Credo.Check.Readability.AliasOrder, []},
            {Credo.Check.Readability.FunctionNames, []},
            {Credo.Check.Readability.LargeNumbers, []},
            {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
            {Credo.Check.Readability.ModuleAttributeNames, []},
            {Credo.Check.Readability.ModuleDoc, []},
            {Credo.Check.Readability.ModuleNames, []},
            {Credo.Check.Readability.ParenthesesInCondition, []},
            {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
            {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
            {Credo.Check.Readability.PredicateFunctionNames, []},
            {Credo.Check.Readability.PreferImplicitTry, []},
            {Credo.Check.Readability.RedundantBlankLines, []},
            {Credo.Check.Readability.Semicolons, []},
            {Credo.Check.Readability.SpaceAfterCommas, []},
            # Publics-only (Credo's default). The repo predates the defp half of
            # the spec mandate in development-philosophy.md § Specs; every public
            # function already carries a @spec. Scoped to lib/ — the spec mandate
            # is about the library's contract surface, and in test/ the check fires
            # on `defapi`-generated endpoint functions and fixture helpers.
            {Credo.Check.Readability.Specs, [include_defp: false, files: %{excluded: [~r"/test/"]}]},
            {Credo.Check.Readability.StringSigils, []},
            {Credo.Check.Readability.TrailingBlankLine, []},
            {Credo.Check.Readability.TrailingWhiteSpace, []},
            {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
            {Credo.Check.Readability.VariableNames, []},
            {Credo.Check.Readability.WithSingleClause, []},

            #
            ## Refactoring opportunities (incl. the AI-slop complements)
            #
            {Credo.Check.Refactor.Apply, []},
            # Perf check about list append; in test/ it fires on keyword-option
            # fixture building (`@opts ++ [description: ...]`), not a hot path.
            {Credo.Check.Refactor.AppendSingleItem, [files: %{excluded: [~r"/test/"]}]},
            {Credo.Check.Refactor.CondStatements, []},
            {Credo.Check.Refactor.CyclomaticComplexity, []},
            {Credo.Check.Refactor.DoubleBooleanNegation, []},
            {Credo.Check.Refactor.FilterCount, []},
            {Credo.Check.Refactor.FilterFilter, []},
            {Credo.Check.Refactor.FunctionArity, []},
            {Credo.Check.Refactor.LongQuoteBlocks, []},
            {Credo.Check.Refactor.MapInto, []},
            {Credo.Check.Refactor.MapJoin, []},
            {Credo.Check.Refactor.MapMap, []},
            {Credo.Check.Refactor.MatchInCondition, []},
            {Credo.Check.Refactor.NegatedConditionsInUnless, []},
            {Credo.Check.Refactor.NegatedConditionsWithElse, []},
            {Credo.Check.Refactor.Nesting, []},
            {Credo.Check.Refactor.RedundantWithClauseResult, []},
            {Credo.Check.Refactor.RejectReject, []},
            {Credo.Check.Refactor.UnlessWithElse, []},
            {Credo.Check.Refactor.WithClauses, []},

            #
            ## Warnings
            #
            {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
            {Credo.Check.Warning.BoolOperationOnSameValues, []},
            {Credo.Check.Warning.Dbg, []},
            {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
            {Credo.Check.Warning.IExPry, []},
            {Credo.Check.Warning.IoInspect, []},
            {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
            {Credo.Check.Warning.OperationOnSameValues, []},
            {Credo.Check.Warning.OperationWithConstantResult, []},
            {Credo.Check.Warning.RaiseInsideRescue, []},
            {Credo.Check.Warning.SpecWithStruct, []},
            {Credo.Check.Warning.UnsafeExec, []},
            {Credo.Check.Warning.UnusedEnumOperation, []},
            {Credo.Check.Warning.UnusedFileOperation, []},
            {Credo.Check.Warning.UnusedKeywordOperation, []},
            {Credo.Check.Warning.UnusedListOperation, []},
            {Credo.Check.Warning.UnusedPathOperation, []},
            {Credo.Check.Warning.UnusedRegexOperation, []},
            {Credo.Check.Warning.UnusedStringOperation, []},
            {Credo.Check.Warning.UnusedTupleOperation, []},
            {Credo.Check.Warning.WrongTestFileExtension, []}
            #
            # An explicit `enabled:` list is authoritative for Credo — plugin-registered
            # checks are silently dropped unless re-listed. Append ExSlop's recommended
            # set (upstream's own snippet).
          ] ++
            Enum.map(ExSlop.recommended_checks(), fn
              # Perf check; `assert length(list) == 3` in test/ is idiomatic
              # assertion style, not a hot path.
              ExSlop.Check.Refactor.LengthComparison = check ->
                {check, [files: %{excluded: [~r"/test/"]}]}

              check ->
                {check, []}
            end),
        disabled: [
          # Handled by `mix format` + Styler.
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.SeparateAliasRequire, []},
          {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.UnsafeToAtom, []}
        ]
      }
    }
  ]
}
