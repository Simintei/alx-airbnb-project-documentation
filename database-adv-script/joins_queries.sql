INNER JOIN
-Joins both the user table and bookings table using (userid,bookingid,propertyid)-guesses
to retrieve all bookings and the respective users(guest) who made the bookings
  
SELECT
 users.first_name, 
 users.last_name, 
 booking.user_id
FROM users
INNER JOIN booking 
 ON users.user_id = booking.user_id;

LEFT JOIN
Returns all records from the left table(properties), and the matching records from the right table(reviews)-property_id,review_id,name
to retrieve all properties and their reviews, including properties that have no reviews.

SELECT
 property.name,
 property.property_id,
 review.review_id
FROM property
LEFT JOIN review 
 ON property.property_id = review.property_id
ORDER BY property.name; 

FULL OUTER JOIN
to retrieve all users and all bookings, even if the user has no booking or a booking is not linked to a user

SELECT
 users.first_name,
 users.last_name,
 users.used_id,
 booking.booking_id
FROM users
FULL OUTER JOIN booking
 ON users.user_id = booking.user_id
ORDER BY users.first_name;
