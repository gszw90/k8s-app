package main

import (
	"fmt"
	"runtime"
	"github.com/gin-gonic/gin"
)

func main() {
	// Initialize the game
	fmt.Println(runtime.GOOS, runtime.GOARCH)
	startServer()
}


func startServer(){
	r:= gin.Default()
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})
	r.GET("/hello", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "hello world",
		})
	})
	// Listen and serve on
	r.Run(":18080") // listen and serve on

}