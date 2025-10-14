package main

import "github.com/gin-gonic/gin"

func main() {
	// Initialize the game
	startServer()
}

// startServer starts the server
func startServer() {
	// Start the server
	r := gin.Default()
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})
	r.GET("/hello", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "hello world,this is second app",
		})
	})

	r.Run(":18081") // listen and serve on
}
