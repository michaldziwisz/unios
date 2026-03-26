# Accessibility Notes

UniOS treats VoiceOver as a product requirement, not a post-build audit.

## Implemented In Code

- Every primary action has visible text plus an accessibility label.
- Conversation rows expose title, summary, timestamp, unread count, mute state, and pinned state.
- Conversation messages expose sender, time, and delivery status in spoken form.
- The composer can receive accessibility focus when a chat opens.
- Contacts and call logs expose direct actions instead of relying on hidden gestures.
- Settings include a dedicated accessibility screen with live VoiceOver status playback.
- Layouts use system text styles and avoid clipping-heavy fixed-height controls.

## Manual Device Verification Still Required

The following cannot be signed off from source code alone:

- VoiceOver rotor order through long conversations
- Dynamic Type at the largest accessibility categories
- Switch Control traversal
- spoken behavior when system audio is already active

Validate these on a physical iPhone before any distribution build is treated as release quality.

