# PSScriptAnalyzer settings for S2DCartographer.
# CI fails on any Error or Warning that is not excluded here. Every exclusion is deliberate.
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # The report, diagram and Invoke-S2DCartographer cmdlets are interactive console tools:
        # progress and result banners are written for the operator, not the pipeline.
        'PSAvoidUsingWriteHost'

        # Generator functions (New-S2D*Svg, New-S2DReport, New-S2DDiagram) build strings or write
        # to an explicit -OutputPath. They do not change system state.
        'PSUseShouldProcessForStateChangingFunctions'

        # Best-effort CIM / WMI probes: a missing property or an older OS must not stop collection.
        'PSAvoidUsingEmptyCatchBlock'

        # Parameters kept for a stable public/internal signature across exporters (Author, Company,
        # IncludeNonPoolDisks ...) even when a given format ignores them.
        'PSReviewUnusedParameter'

        # False positive: the helper functions inside the Invoke-Command script block declare their
        # own parameters, they do not capture caller variables.
        'PSUseUsingScopeModifierInNewRunspaces'
    )
}
