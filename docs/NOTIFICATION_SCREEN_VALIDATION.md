# Notification Screen Implementation – Validation

**Date:** 2025-02-12  
**Scope:** Seeker notification center (bell → NotificationListScreen).

---

## 1. Bell icon opens NotificationListScreen

| Check | Status | Evidence |
|-------|--------|----------|
| Bell in seeker UI | ✅ | `_buildJobFeedTab()` in `_SeekerHomeScreenState`: `IconButton` with `Icons.notifications_none` in the job feed header |
| onPressed navigation | ✅ | `Navigator.of(context).push(MaterialPageRoute(builder: (context) => NotificationListScreen(selectedLanguage: _currentLanguage)))` |
| Screen defined | ✅ | `NotificationListScreen` in `lib/main.dart` with `selectedLanguage` |

**Verdict:** **Pass.** Tapping the bell pushes `NotificationListScreen`.

---

## 2. Notifications load using API

| Check | Status | Evidence |
|-------|--------|----------|
| API call on open | ✅ | `NotificationListScreen` `initState()` → `_loadNotifications()` |
| Endpoint | ✅ | `_apiService.getNotifications(limit: _pageSize, offset: 0)` → `GET /api/notifications?limit=20&offset=0` (with auth) |
| Response handling | ✅ | `res.success && res.data != null` → `_notifications = list`; `ApiService.getNotifications()` parses `response.data!['notifications']` into `List<AppNotification>` |
| Backend | ✅ | `notificationRoutes.js`: `GET /` with `authenticateOwnerOrSeeker`, `pushService.getNotifications(req.userId, req.userType, { limit, offset })`; returns `{ success, data: { notifications, total, limit, offset } }` |

**Verdict:** **Pass.** Notifications are loaded from the API when the screen opens.

---

## 3. Pagination works

| Check | Status | Evidence |
|-------|--------|----------|
| Page size | ✅ | `_pageSize = 20`; `getNotifications(limit: _pageSize, offset: append ? _notifications.length : 0)` |
| Load more trigger | ✅ | `ListView.builder` `itemCount: _notifications.length + (_hasMore ? 1 : 0)`; when `index == _notifications.length`, `addPostFrameCallback` calls `_loadNotifications(append: true)` |
| Has more logic | ✅ | `_hasMore = list.length >= _pageSize` after each load; `_loadingMore` prevents duplicate requests |
| Backend support | ✅ | `pushService.getNotifications(..., { limit, offset })` with `ORDER BY created_at DESC LIMIT $3 OFFSET $4` |

**Verdict:** **Pass.** Pagination is implemented (initial 20, load more when scrolling to the end).

---

## 4. Unread badge updates

| Check | Status | Evidence |
|-------|--------|----------|
| List item unread state | ✅ | `_buildNotificationItem`: unread → background `Color(0xFF3D3D7B).withOpacity(0.06)` and blue dot; title fontWeight w600 when unread |
| Mark read updates list | ✅ | `_markAsRead()` → `markNotificationAsRead(id)` then `setState` with `isRead: true` for that item |
| Bell badge (seeker) | ✅ | `_SeekerHomeScreenState`: `_unreadNotificationCount`; loaded in `_loadData()` via `getUnreadNotificationCount()`; `Badge(isLabelVisible: _unreadNotificationCount > 0, label: Text(...))` around the bell; `_refreshUnreadCount()` after `Navigator.pop()` from NotificationListScreen |
| Unread count API | ✅ | `GET /api/notifications/unread-count` → `pushService.getUnreadCount(userId, userType)`; used by `getUnreadNotificationCount()` |

**Verdict:** **Pass.** List unread styling updates on tap; bell badge shows count and refreshes when returning from the notification screen.

---

## 5. Mark as read updates backend

| Check | Status | Evidence |
|-------|--------|----------|
| Tap handler | ✅ | `_buildNotificationItem`: `InkWell(onTap: () => _markAsRead(notification))` |
| API call | ✅ | `_markAsRead()` → `_apiService.markNotificationAsRead(notification.id)` → `PATCH /api/notifications/:id/read` |
| Backend | ✅ | `notificationRoutes.js`: `PATCH '/:id/read'`, `authenticateOwnerOrSeeker`, `pushService.markAsRead(notificationId, req.userId, req.userType)`; updates `push_notification_log SET is_read = true WHERE id AND user_id AND user_type` |
| Local UI update | ✅ | After PATCH, `setState` with that notification’s `isRead: true` so the row no longer shows as unread |

**Verdict:** **Pass.** Tapping a notification sends PATCH to the backend and updates the list and badge.

---

## 6. Empty state when no notifications exist

| Check | Status | Evidence |
|-------|--------|----------|
| Condition | ✅ | `body: _notifications.isEmpty ? _buildEmptyState() : RefreshIndicator(...)` |
| Copy | ✅ | `_buildEmptyState()`: icon `Icons.notifications_none`, title `_localizations.noNotificationsYet` ("No notifications yet"), subtext `_localizations.noNotificationsSubtext` ("You'll see hiring updates here") |
| Localization | ✅ | `AppLocalizations`: `noNotificationsYet`, `noNotificationsSubtext` (EN + HI) |

**Verdict:** **Pass.** Empty state is shown when the list is empty, with the required text.

---

## Summary

| # | Check | Result |
|---|--------|--------|
| 1 | Bell icon opens NotificationListScreen | ✅ Pass |
| 2 | Notifications load using API | ✅ Pass |
| 3 | Pagination works | ✅ Pass |
| 4 | Unread badge updates | ✅ Pass |
| 5 | Mark as read updates backend | ✅ Pass |
| 6 | Empty state when no notifications | ✅ Pass |

---

## Conclusion

**Notification center works as intended.**

- The seeker notification bell opens `NotificationListScreen`.
- Notifications are loaded from `GET /api/notifications` with pagination (limit/offset).
- Load-more is triggered at the end of the list and uses the same API with increased offset.
- Unread count is shown on the bell and refreshed when leaving the notification screen; list items show unread styling and update when marked read.
- Mark-as-read is sent to `PATCH /api/notifications/:id/read` and the UI is updated.
- Empty state shows "No notifications yet" and the subtext when there are no items.

**Enhancement made during validation:** The seeker home screen now fetches unread count in `_loadData()` and displays a `Badge` on the bell when `_unreadNotificationCount > 0`, and calls `_refreshUnreadCount()` after returning from `NotificationListScreen` so the badge updates after the user marks items read.
