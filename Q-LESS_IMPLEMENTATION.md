# Q-Less Appointment Management System

## Overview
Implemented a comprehensive Q-Less appointment management system for both Hospital and Clinic dashboards with intelligent time slot assignment, bulk delay updates, and automated patient notifications.

## Features Implemented

### 1. **Smart Time Slot Assignment (15-minute intervals)**
- ✅ Time slots generated from 9:00 AM to 9:00 PM in 15-minute intervals
- ✅ Conflict detection: Prevents double-booking of same doctor at same time
- ✅ Case-insensitive doctor name matching (e.g., "Dr. Om" = "dr. om" = "DR. OM")
- ✅ Original time tracking for delay calculations
- ✅ Enhanced UI with scrollable dropdown for 49 time slots per day

### 2. **Bulk Delay Updates with @commands**
- ✅ **@minutes X**: Delay all appointments by X minutes (e.g., `@minutes 10`)
- ✅ **@hour X**: Delay all appointments by X hours (e.g., `@hour 1`)
- ✅ **@sec X**: Delay all appointments by X seconds (e.g., `@sec 30`)
- ✅ Smart time calculation that handles AM/PM transitions
- ✅ Affects only pending/accepted/assigned appointments
- ✅ Preserves original appointment time for cumulative delay tracking

### 3. **Automated Patient Notifications**
- ✅ Patients receive notifications when appointments are delayed
- ✅ Notification includes delay duration and new appointment time
- ✅ Message format: "Dear patient, sorry for the inconvenience. Your appointment has been delayed by X minutes/hours. New time: HH:MM AM/PM"
- ✅ Real-time Socket.IO broadcasting to patient apps

### 4. **Systematic Time-Based Sorting**
- ✅ Appointments automatically sorted by scheduled time (earliest first)
- ✅ Unscheduled appointments appear at the end
- ✅ Proper 12-hour time parsing with AM/PM handling

### 5. **Enhanced Dashboard UI**
- ✅ Q-Less command panel with preset buttons (10min, 15min, 30min, 1hr, 2hr)
- ✅ Custom command input field for flexible delay times
- ✅ Visual feedback with success/error messages
- ✅ Real-time appointment list refresh via Socket.IO
- ✅ Works identically for both Hospital and Clinic dashboards

## Backend Changes

### Modified Files:
1. **`backend/src/store.js`**
   - Added `originalAssignedTime` and `delayMinutes` fields to booking schema
   - Implemented `checkTimeSlotAvailability()` for conflict detection
   - Implemented `bulkDelayAppointments()` for batch updates
   - Added `addMinutesToTime()` helper for time calculations

2. **`backend/src/server.js`**
   - Updated `PATCH /api/bookings/:id` with time slot validation
   - Added `POST /api/hospitals/:id/delay-appointments` endpoint
   - Parses @minutes, @hour, @sec commands
   - Sends bulk notifications to affected patients
   - Emits `appointments:bulk_updated` socket event

## Frontend Changes

### Modified Files:
1. **`apps/bmh_client/lib/main.dart`**
   - Enhanced `TimeSlotPickerDialog` with 15-minute interval generator
   - Added Q-Less bulk delay UI panel in appointments tab
   - Implemented `_bulkDelayAppointments()` API call
   - Added `_sortAppointmentsByTime()` for systematic ordering
   - Added `_compareTimeStrings()` for proper time comparison
   - Created `_BulkDelayDialog` widget with preset options
   - Added socket listener for `appointments:bulk_updated` event

## API Endpoints

### New Endpoint:
```
POST /api/hospitals/:id/delay-appointments
Body: { "command": "@minutes 10" }
Response: {
  "success": true,
  "delayMinutes": 10,
  "updatedCount": 5,
  "bookings": [...]
}
```

### Updated Endpoint:
```
PATCH /api/bookings/:id
Body: {
  "assignedDoctor": "Dr. Smith",
  "assignedTime": "10:30 AM",
  "status": "assigned"
}
Response: 409 Conflict if time slot already taken
```

## Usage Examples

### For Hospital/Clinic Staff:

1. **Assign Appointment with Time Slot:**
   - Click "Assign" on pending appointment
   - Enter doctor name (e.g., "Dr. Ravi")
   - Select time from dropdown (e.g., "10:30 AM")
   - System validates no conflict exists
   - Patient receives notification with doctor and time

2. **Delay All Appointments:**
   - Option A: Type `@minutes 15` in command box and press Enter
   - Option B: Click "Delay All" button, select preset (e.g., "15 minutes")
   - All pending/assigned appointments delayed by 15 minutes
   - Each patient receives personalized delay notification

3. **View Appointments:**
   - Appointments automatically sorted by time (earliest first)
   - Filter by status: ALL, PENDING, ACCEPTED, ASSIGNED, QUEUED, COMPLETED, DECLINED
   - Real-time updates via Socket.IO

## Time Slot Conflict Prevention

The system prevents double-booking through:
- Case-insensitive doctor name comparison
- Case-insensitive time slot comparison
- Only checks active appointments (pending/accepted/assigned)
- Returns 409 Conflict error with clear message

Example:
```
Dr. Om at 10:30 AM = dr. om at 10:30 am = DR. OM at 10:30 AM
All treated as the same slot and will conflict
```

## Delay Calculation Logic

When using `@minutes 10`:
1. System finds all pending/assigned appointments
2. Stores original time if not already stored
3. Adds 10 minutes to original time (not current delayed time)
4. Updates `delayMinutes` field cumulatively
5. Recalculates `assignedTime` from original + total delay
6. Sends notification to patient

Example:
- Original: 10:00 AM
- First delay @minutes 10 → 10:10 AM (delayMinutes: 10)
- Second delay @minutes 5 → 10:15 AM (delayMinutes: 15)
- Original time preserved: 10:00 AM

## Testing Checklist

- [ ] Assign appointment with 15-minute interval time slot
- [ ] Try to assign same doctor at same time (should fail with conflict)
- [ ] Use @minutes 10 to delay all appointments
- [ ] Use @hour 1 to delay all appointments
- [ ] Verify patients receive delay notifications
- [ ] Check appointments are sorted by time
- [ ] Test on both Hospital and Clinic dashboards
- [ ] Verify Socket.IO real-time updates work

## Notes

- Time slots range: 9:00 AM to 9:00 PM (49 slots total)
- Maximum delay: 24 hours (1440 minutes)
- Delay commands are case-insensitive
- Works with MongoDB and in-memory fallback
- Compatible with existing HQR and queue features

## Next Steps (Optional Enhancements)

1. Add visual indicators for delayed appointments
2. Show delay history in appointment details
3. Add "Reset to Original Time" button
4. Implement doctor availability calendar view
5. Add appointment reminders 30 minutes before scheduled time
