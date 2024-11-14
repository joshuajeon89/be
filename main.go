package main

import (
	"github.com/aws/aws-lambda-go/lambda"
	echoadapter "github.com/awslabs/aws-lambda-go-api-proxy/echo" // AWS Lambda adapter for Echo
	"github.com/labstack/echo/v4"
	"lbls.xyz/be/config"
	"lbls.xyz/be/handlers"
)

// Initialize Echo and configure routes
func setupRouter() *echo.Echo {
	e := echo.New()
	client := config.NewDatabaseClient()

	// Register routes
	e.GET("/users", handlers.GetUsers(client))
	e.POST("/users", handlers.CreateUser(client))
	e.GET("/users/:id", handlers.GetUser(client))
	e.PUT("/users/:id", handlers.UpdateUser(client))
	e.DELETE("/users/:id", handlers.DeleteUser(client))

	return e
}

func main() {
	// Initialize Echo instance and adapter
	e := setupRouter()
	adapter := echoadapter.New(e)

	// Start Lambda with the Echo adapter
	lambda.Start(adapter.Proxy)
}
