package com.tiernest.app.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged

data class UiSamplingRequest(val active: Boolean, val refreshPeers: Boolean)

/** Lifecycle visibility alone can outlive a screen-off event. A paused core
 * also has nothing to sample; neither case should keep a UI timer running. */
fun uiSamplingRequests(visible: StateFlow<Boolean>, dataVisible: StateFlow<Boolean>,
                       peersVisible: StateFlow<Boolean>, interactive: StateFlow<Boolean>,
                       coreActive: StateFlow<Boolean>): Flow<UiSamplingRequest> =
    combine(visible, dataVisible, peersVisible, interactive, coreActive) { ui, data, peers, screen, core ->
        UiSamplingRequest(ui && data && screen && core, peers)
    }.distinctUntilChanged()
