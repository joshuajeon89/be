package handlers

import (
	"context"
	"net/http"
	"strconv"

	"github.com/labstack/echo/v4"
	"lbls.xyz/be/ent"
	// Assuming ent generated a package named "user" for your schema
)

type UserRequest struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// CreateUser handler to create a new user with enhanced error handling.
func CreateUser(client *ent.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		u := new(UserRequest)
		if err := c.Bind(u); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid request payload"})
		}
		user, err := client.User.
			Create().
			SetName(u.Name).
			SetEmail(u.Email).
			Save(context.Background())
		if err != nil {
			if ent.IsConstraintError(err) {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "User with this email already exists"})
			}
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to create user"})
		}
		return c.JSON(http.StatusCreated, user)
	}
}

// GetUser handler to retrieve a user by ID with enhanced error handling.
func GetUser(client *ent.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid user ID"})
		}
		user, err := client.User.Get(context.Background(), id)
		if err != nil {
			if ent.IsNotFound(err) {
				return c.JSON(http.StatusNotFound, map[string]string{"error": "User not found"})
			}
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to retrieve user"})
		}
		return c.JSON(http.StatusOK, user)
	}
}

// GetUsers handler to retrieve all users.
func GetUsers(client *ent.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		users, err := client.User.Query().All(context.Background())
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to retrieve users"})
		}
		return c.JSON(http.StatusOK, users)
	}
}

// UpdateUser handler to update a user by ID with enhanced error handling.
func UpdateUser(client *ent.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid user ID"})
		}
		u := new(UserRequest)
		if err := c.Bind(u); err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid request payload"})
		}
		user, err := client.User.
			UpdateOneID(id).
			SetName(u.Name).
			SetEmail(u.Email).
			Save(context.Background())
		if err != nil {
			if ent.IsConstraintError(err) {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "User with this email already exists"})
			}
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to update user"})
		}
		return c.JSON(http.StatusOK, user)
	}
}

// DeleteUser handler to delete a user by ID with enhanced error handling.
func DeleteUser(client *ent.Client) echo.HandlerFunc {
	return func(c echo.Context) error {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "Invalid user ID"})
		}
		err = client.User.DeleteOneID(id).Exec(context.Background())
		if err != nil {
			if ent.IsNotFound(err) {
				return c.JSON(http.StatusNotFound, map[string]string{"error": "User not found"})
			}
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Failed to delete user"})
		}
		return c.NoContent(http.StatusNoContent)
	}
}
