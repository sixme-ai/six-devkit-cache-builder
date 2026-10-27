package dev.offline.cache;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** Verifies Failsafe's JUnit provider without requiring an external database. */
class OfflineCacheIT {
    @Test
    void integrationProviderLoads() {
        assertTrue(OfflineCacheSeed.sum(1, 1) == 2);
    }
}
