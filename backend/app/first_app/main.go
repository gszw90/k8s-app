package main

import (
	"fmt"
	"runtime"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	// Initialize the game
	fmt.Println(runtime.GOOS, runtime.GOARCH)
	startServer()
}

func startServer() {
	r := gin.Default()
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})
	r.GET("/hello", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "hello world,this is first app",
		})
	})
	r.GET("/info", func(ctx *gin.Context) {
		ctx.JSON(200, gin.H{
			"message": "info",
			"data": map[string]interface{}{
				"os":         runtime.GOOS,
				"arch":       runtime.GOARCH,
				"goroutines": fmt.Sprintf("%d", runtime.NumGoroutine()),
				"version":    runtime.Version(),
				"cpus":       runtime.NumCPU(),
				"time":       time.Now().Format("2006-01-02 15:04:05"),
			},
		})
	})
	// Listen and serve on
	r.Run(":18080") // listen and serve on

}
