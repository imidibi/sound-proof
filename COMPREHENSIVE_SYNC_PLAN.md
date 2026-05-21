# Comprehensive Bidirectional Sync Implementation Plan

## Current Status
✅ Model updated with sync tracking fields (`lastModifiedAt`, `needsUpload`, `isDeleted`)

## Implementation Steps

### Phase 1: Core Sync Infrastructure (IMMEDIATE - Critical for Beta)

#### 1.1 Auto-Upload Unsyncced Mixes
**Location**: `ProjectSyncService.swift`

Add new function:
```swift
func syncUnsyncedMixesToCloud(modelContext: ModelContext) async throws {
    // Find all mixes where needsUpload == true OR (isUploaded == false AND has local file)
    // For each mix:
    //   - Get project/song info
    //   - Call uploadMix()
    //   - Mark as uploaded
}
```

Call this from:
- `ContentView.task` (on app launch after initial sync)
- Network reconnect handler
- Manual sync button

#### 1.2 Mark Mixes for Upload
**Location**: `ImportMixSheet.swift`, anywhere mixes are modified

When creating/modifying mixes:
```swift
mix.needsUpload = true
mix.lastModifiedAt = Date()
```

#### 1.3 Detect Failed Uploads
**Location**: `ProjectSyncService.uploadMix()`

On upload failure:
```swift
catch {
    mix.needsUpload = true  // Retry later
    throw error
}
```

### Phase 2: Timestamp-Based Conflict Resolution

#### 2.1 Compare Timestamps During Sync
When downloading mixes from cloud:
```swift
if localMix.lastModifiedAt > cloudMix.updatedAt {
    // Local is newer - upload to cloud
} else {
    // Cloud is newer - download to local
}
```

#### 2.2 Update Firestore Schema
Add `updatedAt` timestamp to mix documents in Firestore

### Phase 3: Deletion Propagation

#### 3.1 Soft Delete Locally
**Location**: `ProjectListView.deleteMix()`

Instead of immediate delete:
```swift
mix.isDeleted = true
mix.lastModifiedAt = Date()
mix.needsUpload = true
```

#### 3.2 Sync Deletions to Cloud
Upload deletion marker to Firestore

#### 3.3 Process Cloud Deletions
Download deletion markers and remove local mixes

### Phase 4: Background Sync

#### 4.1 Periodic Sync Timer
Run every 5 minutes while app is active

#### 4.2 Network State Monitoring
Already exists - enhance to trigger full sync

## Testing Checklist

- [ ] Create mix on Device A → appears on Device B
- [ ] Modify mix on Device A → updates on Device B
- [ ] Delete mix on Device A → removed from Device B
- [ ] Create mix offline → uploads when online
- [ ] Upload fails → retries on next sync
- [ ] Conflict resolution → cloud wins
- [ ] Multiple devices → all stay in sync

## Migration Strategy

**Existing Data**: Mixes created before this update will have:
- `lastModifiedAt` = current date (set by init default)
- `needsUpload` = false (already uploaded or will be marked during next import)
- `isDeleted` = false

SwiftData will automatically migrate the schema.

## Rollout Plan

1. **Immediate** (today): Implement Phase 1 (auto-upload unsyncced)
2. **This week**: Phases 2-3 (conflicts & deletions)
3. **Next week**: Phase 4 (background sync) + extensive testing

## Risk Mitigation

- All changes are additive (no data loss)
- Soft deletes allow recovery
- Cloud is source of truth for conflicts
- Extensive logging for debugging

---

## Next Steps

Should I proceed with **Phase 1 implementation** now? This will:
- Add auto-sync of unsyncced mixes on app launch
- Fix the immediate problem you experienced
- Take ~30-45 minutes to implement and test

Phases 2-4 can follow in subsequent sessions.
