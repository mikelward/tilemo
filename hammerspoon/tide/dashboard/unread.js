// Unread counts from page titles (SPEC.md §10.3): Gmail, Chat and Calendar
// put one in the title, like "Inbox (3) - Gmail" or "Chat (1,204)".

// The sites the settings start with; each still needs its access allowed.
export const DEFAULT_SITES = ["https://mail.google.com", "https://chat.google.com", "https://calendar.google.com"];

// The first parenthesized count in `title`, else 0.
export function unreadCount(title) {
  const m = /\((\d[\d,]*)\+?\)/.exec(title ?? "");
  return m ? Number(m[1].replaceAll(",", "")) : 0;
}
