const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin SDK
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// -------------------------
// Create Notification (onCreate)
// -------------------------
exports.scheduleEventNotification = functions.firestore
    .document("users/{userId}/events/{eventId}")
    .onCreate(async (snap, context) => {
      const event = snap.data();
      const userId = context.params.userId;
      const eventDate = event.date.toDate();
      const title = event.title;

      const timeRemaining = eventDate - Date.now();

      if (timeRemaining <= 0) {
        console.log("❌ Event is in the past.");
        return null;
      }

      if (timeRemaining > 24 * 60 * 60 * 1000) {
        console.log("⏩ Event is more than 24 hours away. Skipping reminder.");
        return null;
      }

      try {
        const existing = await admin.firestore().collection("userNotifications")
            .where("userId", "==", userId)
            .where("eventTitle", "==", title)
            .where("type", "==", "calendar")
            .get();

        if (!existing.empty) {
          console.log("⚠️ Notification already exists for event:", title);
          return null;
        }

        await admin.firestore().collection("userNotifications").add({
          userId,
          title: "Event Reminder",
          body: `Tomorrow you have the event: ${title}`,
          type: "calendar",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
          eventDate: admin.firestore.Timestamp.fromDate(eventDate),
          eventTitle: title,
        });

        console.log("✅ Created event reminder for:", title);
      } catch (error) {
        console.error("🔥 Failed to schedule notification:", error);
      }

      return null;
    });


// -------------------------
// Update Notification (onUpdate)
// -------------------------
exports.updateEventNotification = functions.firestore
    .document("users/{userId}/events/{eventId}")
    .onUpdate(async (change, context) => {
      const after = change.after.data();
      const userId = context.params.userId;
      const eventTitle = after.title;
      const eventDate = after.date.toDate();

      const timeRemaining = eventDate - Date.now();
      if (timeRemaining <= 0) {
        console.log("❌ Event is in the past.");
        return null;
      }

      if (timeRemaining > 24 * 60 * 60 * 1000) {
        console.log("⏩ Event is more than 24 hours away. Skipping reminder.");
        return null;
      }

      try {
      // Delete old notifications for this event
        const existing = await admin.firestore().collection("userNotifications")
            .where("userId", "==", userId)
            .where("eventTitle", "==", eventTitle)
            .where("type", "==", "calendar")
            .get();

        existing.forEach((doc) => doc.ref.delete());

        // Only recreate if within 24 hours
        if (timeRemaining <= 24 * 60 * 60 * 1000) {
          await admin.firestore().collection("userNotifications").add({
            userId,
            title: "Event Reminder",
            body: `Tomorrow you have the event22: ${eventTitle}`,
            type: "calendar",
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false,
            eventDate: admin.firestore.Timestamp.fromDate(eventDate),
            eventTitle: eventTitle,
          });

          console.log("🔁 Updated reminder for:", eventTitle);
        }
      } catch (error) {
        console.error("🔥 Failed to update notification:", error);
      }

      return null;
    });


// -------------------------
// Delete Notification (onDelete)
// -------------------------
exports.deleteEventNotification = functions.firestore
    .document("users/{userId}/events/{eventId}")
    .onDelete(async (snap, context) => {
      const event = snap.data();
      const userId = context.params.userId;
      const eventTitle = event.title;

      try {
        const snapshot = await admin.firestore().collection("userNotifications")
            .where("userId", "==", userId)
            .where("eventTitle", "==", eventTitle)
            .where("type", "==", "calendar")
            .get();

        snapshot.forEach((doc) => doc.ref.delete());

        console.log("🗑️ Deleted event reminder for:", eventTitle);
      } catch (error) {
        console.error("🔥 Failed to delete reminder:", error);
      }

      return null;
    });
// -------------------------
// Background Checker (Cron Job)
// -------------------------
exports.autoScheduleEventReminders = functions.pubsub
    .schedule("every 1 minutes")
    .timeZone("Asia/Kuala_Lumpur") // Change if needed
    .onRun(async () => {
      const now = new Date();
      const twentyFourHoursFromNow =
      new Date(now.getTime() + 24 * 60 * 60 * 1000);

      try {
        const usersSnapshot = await admin.firestore().collection("users").get();

        for (const userDoc of usersSnapshot.docs) {
          const userId = userDoc.id;
          const eventsSnapshot = await admin
              .firestore()
              .collection(`users/${userId}/events`)
              .where("date", ">", now)
              .where("date", "<=", twentyFourHoursFromNow)
              .get();

          for (const eventDoc of eventsSnapshot.docs) {
            const event = eventDoc.data();
            const eventId = eventDoc.id;
            const title = event.title;
            const eventDate = event.date.toDate();

            // Check if notification already exists
            const notifSnapshot = await admin.firestore()
                .collection("userNotifications")
                .where("userId", "==", userId)
                .where("eventId", "==", eventId)
                .where("type", "==", "calendar")
                .get();

            if (notifSnapshot.empty) {
              await admin.firestore().collection("userNotifications").add({
                userId,
                title: "Event Reminder",
                body: `Tomorrow you have the event44: ${title}`,
                type: "calendar",
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
                eventId,
                eventTitle: title,
                eventDate: admin.firestore.Timestamp.fromDate(eventDate),
              });

              console.log(`✅ Scheduled reminder for ${title} (user ${userId})`);
            }
          }
        }
      } catch (error) {
        console.error("🔥 Cron job failed:", error);
      }

      return null;
    });
// -------------------------
// Background Checker (Cron Job)
// -------------------------
exports.autoScheduleEventReminders = functions.pubsub
    .schedule("every 1 minutes")
    .timeZone("Asia/Kuala_Lumpur") // Change if needed
    .onRun(async () => {
      const now = new Date();
      const twentyFourHoursFromNow =
       new Date(now.getTime() + 24 * 60 * 60 * 1000);

      try {
        const usersSnapshot = await admin.firestore().collection("users").get();

        for (const userDoc of usersSnapshot.docs) {
          const userId = userDoc.id;
          const eventsSnapshot = await admin
              .firestore()
              .collection(`users/${userId}/events`)
              .where("date", ">", now)
              .where("date", "<=", twentyFourHoursFromNow)
              .get();

          for (const eventDoc of eventsSnapshot.docs) {
            const event = eventDoc.data();
            const eventId = eventDoc.id;
            const title = event.title;
            const eventDate = event.date.toDate();

            // Check if notification already exists
            const notifSnapshot = await admin.firestore()
   .collection("userNotifications")
  .where("userId", "==", userId)
  .where("eventTitle", "==", title)
  .where("eventDate", "==", admin.firestore.Timestamp.fromDate(eventDate))
  .where("type", "==", "calendar")
  .get();

            if (notifSnapshot.empty) {
              await admin.firestore().collection("userNotifications").add({
                userId,
                title: "Event Reminder",
                body: `Tomorrow you have the event55: ${title}`,
                type: "calendar",
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
                eventId,
                eventTitle: title,
                eventDate: admin.firestore.Timestamp.fromDate(eventDate),
              });

              console.log(`✅ Scheduled reminder for ${title} (user ${userId})`);
            }
          }
        }
      } catch (error) {
        console.error("🔥 Cron job failed:", error);
      }

      return null;
    });

