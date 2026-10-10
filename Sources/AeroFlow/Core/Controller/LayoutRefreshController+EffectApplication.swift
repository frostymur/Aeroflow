// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AppKit
import Foundation
import QuartzCore

extension LayoutRefreshController {
    func executeLayoutPlans(
        _ plans: [WorkspaceLayoutPlan],
        suppressWindowActivation: Bool
    ) -> [WorkspaceDescriptor.ID: AcceptedSeq] {
        var acceptedSeqs: [WorkspaceDescriptor.ID: AcceptedSeq] = [:]
        for plan in plans {
            if let acceptedSeq = executeLayoutPlanReturningAcceptedSeq(
                plan,
                suppressWindowActivation: suppressWindowActivation
            ) {
                acceptedSeqs[plan.workspaceId] = acceptedSeq
            }
        }
        return acceptedSeqs
    }

    func publishAcceptedLayoutSurfaces(_ plan: WorkspaceLayoutPlan, controller: WMController) {
        controller.surfaceReconciler.applyAcceptedNativeFullscreenSlots(
            plan.diff.nativeFullscreenSlots,
            workspaceId: plan.workspaceId,
            displayId: plan.monitor.displayId,
            displayContext: NativeFullscreenDisplayContext(
                workingFrame: plan.monitor.workingFrame,
                scale: plan.monitor.scale
            )
        )
        controller.surfaceReconciler.applyAcceptedTabRailGeometry(
            plan.diff.tabRailGeometryCommands,
            workspaceId: plan.workspaceId,
            displayId: plan.monitor.displayId
        )
    }

    func applyEffectPlan(_ plan: EffectPlan, controller: WMController) {
        var currentEffectActiveWorkspaceIds: Set<WorkspaceDescriptor.ID>?
        if plan.effects.visibility != nil {
            let activeWorkspaceIds = currentActiveWorkspaceIds()
            currentEffectActiveWorkspaceIds = activeWorkspaceIds
            rebuildInactiveWorkspaceWindowSet(activeWorkspaceIds: activeWorkspaceIds)
        }

        let actionWorkspacesCurrentAtEntry = plan.postLayoutActions.map {
            $0.currentWorkspaces(using: controller.workspaceManager)
        }
        let forwardedPostLayoutActions = { (acceptedSeqs: [WorkspaceDescriptor.ID: AcceptedSeq]) in
            zip(plan.postLayoutActions, actionWorkspacesCurrentAtEntry).map { action, currentAtEntry in
                action.forwarded(by: acceptedSeqs, currentAtEntry: currentAtEntry)
            }
        }

        var acceptedSeqs = executeLayoutPlans(
            plan.workspacePlans,
            suppressWindowActivation: plan.effects.suppressWindowActivation
        )
        layoutState.didExecuteEffectPlan = true

        applyEffectVisibility(
            plan, controller: controller,
            activeWorkspaceIds: &currentEffectActiveWorkspaceIds, acceptedSeqs: &acceptedSeqs
        )

        let activeWorkspaceIdsForFocusValidation = currentEffectActiveWorkspaceIds ?? currentActiveWorkspaceIds()
        for workspaceId in plan.effects.focusValidationWorkspaceIds
            where activeWorkspaceIdsForFocusValidation.contains(workspaceId)
        {
            let preferredRecoveryToken = plan.effects.focusValidationPreferredTokens[workspaceId]
            controller.ensureFocusedTokenValid(
                in: workspaceId,
                preferredRecoveryToken: preferredRecoveryToken
            )
        }

        for postLayoutAction in forwardedPostLayoutActions(acceptedSeqs) {
            postLayoutAction.runIfCurrent(using: controller.workspaceManager)
        }

        requestFollowUpRelayoutForStaleRestores(plan, controller: controller)

        completeEffectPlan(plan, controller: controller)
    }

    private func requestFollowUpRelayoutForStaleRestores(
        _ plan: EffectPlan,
        controller: WMController
    ) {
        let activeIds = currentActiveWorkspaceIds()
        var followUps = Set<WorkspaceDescriptor.ID>()
        for workspacePlan in plan.workspacePlans {
            let workspaceId = workspacePlan.workspaceId
            let diff = workspacePlan.diff
            let hasFramelessRestore = diff.restoreChanges.contains { restore in
                !diff.frameChanges.contains { $0.token == restore.token }
            }
            let layoutWasEmpty = diff.frameChanges.isEmpty
            guard layoutWasEmpty || hasFramelessRestore else {
                layoutState.relayoutFollowUpBlocked.remove(workspaceId)
                continue
            }
            DiagnosticsEventRecorder.shared.recordLifecycle(
                name: "relayout.followup.stale empty=\(layoutWasEmpty) restore=\(hasFramelessRestore)"
            )
            guard activeIds.contains(workspaceId),
                  !layoutState.relayoutFollowUpBlocked.contains(workspaceId),
                  !controller.workspaceManager.entries(in: workspaceId).isEmpty
            else {
                if activeIds.contains(workspaceId), layoutState.relayoutFollowUpBlocked.contains(workspaceId) {
                    DiagnosticsEventRecorder.shared.recordLifecycle(name: "relayout.followup.blocked")
                }
                continue
            }
            followUps.insert(workspaceId)
        }
        guard !followUps.isEmpty else { return }
        layoutState.relayoutFollowUpBlocked.formUnion(followUps)
        DiagnosticsEventRecorder.shared.recordLifecycle(
            name: "relayout.followup.requested n=\(followUps.count)"
        )
        requestImmediateRelayout(reason: .workspaceTransition, affectedWorkspaceIds: followUps)
    }

    private func applyEffectVisibility(
        _ plan: EffectPlan,
        controller: WMController,
        activeWorkspaceIds: inout Set<WorkspaceDescriptor.ID>?,
        acceptedSeqs: inout [WorkspaceDescriptor.ID: AcceptedSeq]
    ) {
        if plan.effects.visibility != nil {
            let resolvedActiveWorkspaceIds = activeWorkspaceIds ?? currentActiveWorkspaceIds()
            activeWorkspaceIds = resolvedActiveWorkspaceIds
            controller.withRuntimeFrameJobCancellationSuppressed {
                restoreWorkspaceInactiveFloatingWindows(activeWorkspaceIds: resolvedActiveWorkspaceIds)
                hideInactiveWorkspaces(activeWorkspaceIds: resolvedActiveWorkspaceIds)
            }
            for workspaceId in Array(acceptedSeqs.keys) {
                guard let accepted = acceptedSeqs[workspaceId] else { continue }
                acceptedSeqs[workspaceId] = AcceptedSeq(
                    after: controller.workspaceManager.worldSeq,
                    domains: accepted.domains
                )
            }
        }
    }

    private func completeEffectPlan(_ plan: EffectPlan, controller: WMController) {
        if plan.effects.markInitialRefreshComplete {
            layoutState.hasCompletedInitialRefresh = true
        }

        if plan.effects.drainDeferredCreatedWindows {
            controller.axEventHandler.drainDeferredCreatedWindows()
        }

        if plan.effects.subscribeManagedWindows {
            controller.axEventHandler.subscribeToManagedWindows()
        }
        workspaceSwipe.warmPreviews()
    }
}

extension LayoutRefreshController {
    @discardableResult
    func executeLayoutPlan(_ plan: WorkspaceLayoutPlan) -> Bool {
        executeLayoutPlanReturningAcceptedSeq(plan, suppressWindowActivation: false) != nil
    }

    func executeLayoutPlanReturningAcceptedSeq(
        _ plan: WorkspaceLayoutPlan,
        suppressWindowActivation: Bool = false
    ) -> AcceptedSeq? {
        guard let controller else { return nil }
        guard plan.sessionPatch.plannedSeq == 0
            || controller.workspaceManager.isSeqCurrent(
                plan.sessionPatch.plannedSeq,
                for: plan.workspaceId,
                domains: .layoutCommit.union(.focusCommit)
            )
        else {
            return nil
        }
        if let disposition = plan.dwindleAnimationTargetDisposition,
           !dwindleHandler.canAcceptAnimationTarget(
               disposition,
               workspaceId: plan.workspaceId,
               monitor: plan.monitor
           )
        {
            return nil
        }

        applyLayoutMutations(plan, controller: controller)
        publishAcceptedLayoutSurfaces(plan, controller: controller)
        if let disposition = plan.dwindleAnimationTargetDisposition {
            acceptDwindleAnimationTarget(
                disposition,
                workspaceId: plan.workspaceId,
                displayId: plan.monitor.displayId,
                plannedSeq: controller.workspaceManager.worldSeq
            )
        }
        applyAnimationDirectives(
            plan.animationDirectives,
            workspaceId: plan.workspaceId,
            focusSeqAccepted: true,
            suppressWindowActivation: suppressWindowActivation
        )
        if !plan.isAnimationTick {
            controller.surfaceReconciler.noteWorldChanged()
        }
        return AcceptedSeq(
            after: controller.workspaceManager.worldSeq,
            domains: .layoutCommit.union(.focusCommit)
        )
    }
}
