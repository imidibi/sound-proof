Audio Review & Approval App
Product and MVP Specification for Mac, iPad, and iPhone
App name: Approvl
A native Apple-first companion app for producers, engineers, studios, and clients to review audio, collect timestamped feedback, consolidate notes, and approve mix versions.
1. Executive Summary
Approvl is a native Apple app built from one shared SwiftUI codebase for macOS, iPadOS, and iOS. It is designed to solve the communication chaos around mix reviews, podcast edits, commercial audio, post-production, and studio approvals.
•    Core promise: send a mix, collect timestamped notes, and get approval without email or text-message chaos.
•    Primary buyer: producer, engineer, studio owner, podcast editor, composer, or post-audio team.
•    Primary reviewer: artist, client, label, manager, director, agency stakeholder, or podcast host.
•    Initial platform strategy: Apple-native first, with iPhone support as a key differentiator for fast review on the move.
•    Long-term opportunity: become the workflow layer around DAW sessions rather than another audio processing tool.
2. Product Hypothesis
Professional audio review is still fragmented. Clients leave notes in texts, emails, voice memos, screenshots, and spreadsheets. Producers then translate scattered opinions into revision tasks. The app wins by making review notes timeline-specific, version-aware, collaborative, and actionable.
Assumption    Why it matters    MVP validation signal
Review chaos is painful enough to pay for    Producers spend non-billable time interpreting scattered comments    Users import real mixes and invite real reviewers
Timestamped feedback is more valuable than generic file sharing    Audio feedback needs time context    Most comments are created from the waveform/timeline
iPhone review matters    Producers and clients often listen in cars, taxis, airports, and green rooms    Meaningful approval or comment activity happens on iPhone
Apple-first is sufficient for early validation    Many music and production users already use Mac/iPhone/iPad    Early customers accept iCloud-based collaboration

3. Personas
Persona    Needs    Primary device    Paid?
Mix engineer / producer    Send revisions, gather notes, compare versions, close approvals    Mac and iPad    Yes
Studio owner    Organize projects, clients, deliverables, approvals    Mac    Yes
Podcast editor    Collect host/client notes tied to timestamps    Mac and iPhone    Yes
Artist or client    Listen, leave simple feedback, approve final    iPhone and iPad    Usually free
Label / agency stakeholder    Review multiple versions quickly, consolidate team feedback    Mac and iPhone    Possibly enterprise later

4. Platform Strategy: One Codebase, Three Experiences
The app should share models, business logic, sync, waveform generation, playback services, and most SwiftUI views across Mac, iPad, and iPhone. Each platform gets an optimized layout and interaction model rather than a separate product.
Platform    Role in product    Experience priority
Mac    Producer command center    Project management, import/export, version management, consolidation, PDF/CSV exports
iPad    Focused review and studio couch workflow    Large waveform, Pencil markup, attended sessions, tactile navigation
iPhone    Fast mobile review    Listen, jump to comments, record voice notes, approve/request changes, quick triage

5. MVP Definition
The MVP should not attempt DAW integration, stem mixing, AI, or web sharing at launch. The first release should prove that users will import a mix, share it, receive useful timeline feedback, and close an approval loop.
•    Import one or more stereo audio files per project.
•    Generate and display a waveform.
•    Create timestamped text comments.
•    Create timestamped voice comments.
•    Invite reviewers through iCloud/CloudKit sharing.
•    Support Mac, iPad, and iPhone from one SwiftUI codebase.
•    Track versions and approval state.
•    Export a revision checklist.
6. Core Use Cases
Use case    Description    MVP priority
Mix review    Producer uploads Mix V1 and invites artist/client to leave timestamped notes    P0
Mobile approval    Reviewer listens on iPhone in taxi or airport and approves or requests changes    P0
Voice feedback    Reviewer records spoken feedback at a specific timestamp    P0
Version review    Producer uploads Mix V2 and tracks whether issues are resolved    P0
Comment consolidation    Producer turns multiple comments into a single actionable revision task    P1
Pencil markup    iPad user draws on waveform or timeline region    P1
Stem-specific comments    Reviewer targets vocal/drums/instrumental stem    P2

7. MVP Functional Requirements
Feature    Requirement    Priority
Project creation    User can create a project with name, client, notes, and status.    P0
Audio import    User can import WAV, AIFF, MP3, M4A from Files/Finder.    P0
Waveform rendering    App generates cached waveform peaks for smooth scrolling and zooming.    P0
Playback controls    Play, pause, scrub, skip, and jump to comments.    P0
Timestamp comments    Text comments attach to an exact timestamp and optional time range.    P0
Voice notes    User can record a short voice note attached to timestamp.    P0
Version management    User can add Mix V1, V2, Master V1, etc.    P0
Review invite    Owner can share project with reviewers through iCloud sharing.    P0
Approval state    Each reviewer can mark Pending, Approved, or Changes Requested.    P0
Comment status    Owner can mark comments Open, Done, Rejected, or Resolved.    P0
iPhone quick review    Compact UI optimized for listening and leaving quick notes.    P0
Export notes    Owner can export comments/revision checklist as PDF, CSV, or text.    P1
Drawing markup    User can draw annotations on iPad and Mac.    P1
Manual consolidation    Owner can combine several comments into a revision task.    P1

8. Screen-Level Specification
8.1 Mac App
•    Project sidebar: active projects, archived projects, recent reviews, clients.
•    Main waveform panel: audio playback, zoom, comment pins, selected region.
•    Top toolbar: import audio, add version, invite reviewers, export notes.
•    Right inspector: comments, approval status, reviewer list, selected comment details.
•    Version selector: switch between V1, V2, Master, etc. while preserving playback timestamp.
8.2 iPad App
•    Large waveform-first review screen.
•    Bottom sheet for comments and approvals.
•    Apple Pencil mode for drawing annotations.
•    Studio mode for couch/attended review sessions.
•    Touch-friendly transport controls and scrub gestures.
8.3 iPhone App
•    Quick review mode optimized for one-handed use.
•    Large play/pause button, 15-second skip controls, and comment button.
•    Voice note first: hold to record feedback at current timestamp.
•    Comment inbox: jump through open comments and reply quickly.
•    Approval action always visible: Approve or Request Changes.
•    Offline listen/comment draft support for travel scenarios.
9. Detailed MVP User Flows
9.1 Producer Creates Review
1.    Open app on Mac or iPad.
2.    Create new project.
3.    Import stereo mix file.
4.    App analyzes duration, sample rate, channels, and waveform peaks.
5.    Rename imported audio as Mix V1.
6.    Add reviewer names/emails or iCloud participants.
7.    Share project.
8.    Monitor comments and approval status.
9.2 Reviewer Leaves iPhone Feedback
9.    Open shared review on iPhone.
10.    Tap play.
11.    Tap comment or hold record while listening.
12.    Comment is attached to current timestamp.
13.    Optionally mark section as issue or approval blocker.
14.    Submit feedback.
15.    At end, choose Approved or Changes Requested.
9.3 Producer Handles Revisions
16.    Open comments inspector.
17.    Filter by open comments or approval blockers.
18.    Jump to each timestamp.
19.    Mark as resolved, rejected, or convert to task.
20.    Upload Mix V2.
21.    Ask reviewers to re-review only unresolved items.
10. Data Model
Entity    Key fields    Notes
Project    id, name, clientName, ownerUserID, createdAt, updatedAt, status    Top-level shared object
AudioVersion    id, projectID, name, versionNumber, assetID, duration, sampleRate, channels, approvalStatus    One imported mix or master
Comment    id, projectID, versionID, authorID, timestamp, endTimestamp, text, voiceNoteAssetID, drawingAssetID, status    Core review unit
Reviewer    id, projectID, displayName, email, role, inviteStatus    Participant record
Approval    id, versionID, reviewerID, status, note, createdAt    Per-reviewer approval record
RevisionTask    id, projectID, title, sourceCommentIDs, status, ownerNote    Optional P1 consolidation layer
Asset    id, type, localURL, cloudAssetReference, sizeBytes, checksum    Audio, voice note, drawing, waveform cache

11. Technical Architecture
•    Language/UI: Swift and SwiftUI.
•    Audio: AVFoundation for playback, metadata, and recording voice notes.
•    Persistence: SwiftData or Core Data for local database.
•    Sync: CloudKit with private database for owner data and shared database for collaboration.
•    Files: Security-scoped bookmarks on Mac/iPad/iPhone where needed.
•    Drawing: PencilKit for iPad and compatible markup representation for Mac/iPhone viewing.
•    Export: PDF generation for review summaries and CSV/text for DAW-adjacent task lists.
Layer    Responsibility    Shared across platforms?
Models    Project, AudioVersion, Comment, Reviewer, Approval    Yes
Services    Audio playback, waveform generation, sync, export    Yes
ViewModels    State and business logic for SwiftUI screens    Mostly yes
Views    Reusable components: waveform, comment list, player controls    Mostly yes
Platform shells    Windowing, file picker behavior, compact navigation    Platform-specific

12. Non-Functional Requirements
Area    Requirement
Performance    Waveform should render progressively and remain scrollable for long files.
Offline    Users can play cached audio and draft comments offline, then sync later.
Reliability    Uploads and sync should be resumable and show clear status.
Privacy    Projects are private by default; shared only with invited reviewers.
Accessibility    Support Dynamic Type where reasonable, VoiceOver labels, keyboard navigation on Mac.
Battery    iPhone playback and waveform rendering should avoid excessive background processing.

13. Risks and De-Risking Plan
Risk    Impact    De-risking test
CloudKit sharing friction    Could make client onboarding harder    Prototype invite flow with two Apple IDs before building full app
Large audio files    Upload failures or slow sync    Test 50 MB, 250 MB, and 1 GB assets early
iPhone UX too cramped    Mobile review may be frustrating    Prototype voice-first interaction with minimal waveform controls
Non-Apple clients excluded    Limits market    Validate Apple-first niche before building web backend
Waveform performance    Poor perception of quality    Build waveform cache and progressive rendering early

14. Build Roadmap
Phase    Goal    Deliverables
Phase 0: Prototype    Prove core interaction    Import audio, waveform, playback, local timestamp comments
Phase 1: MVP Alpha    Useful single-user app    Projects, versions, comments, voice notes, local persistence
Phase 2: Collaboration    Prove review workflow    CloudKit sharing, reviewer roles, approvals, sync conflict handling
Phase 3: Mobile polish    Make iPhone valuable    Quick review mode, offline drafts, voice-first comments, push notifications
Phase 4: Studio workflow    Improve paid value    Exports, manual consolidation, client archive, branding

15. MVP Success Metrics
•    Time from import to shared review: under 2 minutes.
•    Reviewer can leave first comment without training: under 30 seconds after opening project.
•    At least 60 percent of reviewed projects receive timestamped comments rather than generic notes.
•    At least 25 percent of review activity happens on iPhone, validating mobile-on-the-run use case.
•    At least 30 percent of projects use version upload and approval state.
•    Early paying users report reduced review chaos or fewer scattered text/email notes.
16. Post-MVP Backlog
•    AI comment grouping and revision summary.
•    A/B version comparison with loudness matching.
•    Stem-specific review and solo/mute groups.
•    Web reviewer portal for non-Apple users.
•    DAW export/import helpers and markers.
•    Studio branding and client portal.
•    Team workspaces and billing.
•    Push notifications for new comments, approvals, and uploads.
17. Appendix: Suggested MVP Object Status Values
Object    Statuses
Project    Draft, In Review, Revisions Needed, Approved, Archived
AudioVersion    Draft, Shared, In Review, Approved, Superseded
Comment    Open, Resolved, Rejected, Converted to Task
Approval    Pending, Approved, Changes Requested
Reviewer Invite    Not Sent, Sent, Accepted, Declined, Removed


