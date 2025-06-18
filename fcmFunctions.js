const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// Trigger function using Firestore document update (v2 version)
exports.sendStatusUpdateNotification = functions
    .runWith({memory: "256MB", timeoutSeconds: 60}) // optional config
    .firestore.document("userReports/{userReportId}")
    .onUpdate(async (change, context) => {
      const before = change.before.data();
      const after = change.after.data();

      // Check if 'status' or 'adminReply' fields are updated
      if (before.status !== after.status ||
        before.adminReply !== after.adminReply) {
        const userId = after.userId; // Get the userId
        const userRef = db.collection("users").doc(userId);
        const userDoc = await userRef.get();

        if (!userDoc.exists) {
          console.log("User not found! Print:", userId);
          return null;
        }

        const user = userDoc.data();
        const fcmToken = user.fcmToken; // Get the user's FCM token

        let notificationTitle = "";
        let notificationBody = "";

        // Check if status changed
        if (after.status !== before.status) {
          notificationTitle = "Report Status Updated";
          notificationBody =
          `Your report status has been updated to: ${after.status}`;
        }

        // Check if adminReply was added or changed
        if (after.adminReply &&
            after.adminReply !== before.adminReply) {
          notificationTitle = "Admin Reply";
          notificationBody =
          `The admin has replied to your report: ${after.adminReply}`;
        }

        // If FCM token exists, send the notification
        if (fcmToken) {
          const message = {
            notification: {
              title: notificationTitle,
              body: notificationBody,
            },
            token: fcmToken, // The recipient user's FCM token
          };

          try {
            await messaging.send(message);
            console.log("Notification sent to user:", userId);
          } catch (error) {
            console.error("Error sending notification:", error);
          }
        } else {
          console.log("FCM token not found for user:", userId);
        }
      }

      return null;
    });
