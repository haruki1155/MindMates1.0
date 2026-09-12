# Student ID validation

The supplied `Validation- School ID..txt` contains the complete set of student IDs:
`2022`, `2023`, `2024`, `2025`, and `2026`, each with sequence numbers `0001` through
`9999` (49,995 IDs total). The callable registration backend validates this structure
and claims the exact ID in `student_id_reservations/{studentId}`. A reservation is
permanent by design, including when a student enters an ID incorrectly; an administrator
must handle any correction.
