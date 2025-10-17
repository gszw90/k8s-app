package main

import (
	"flag"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/goccy/go-yaml"
)

type Config struct {
	Name string `yaml:"name"`
	Mode string `yaml:"mode"`
}

var config Config
var c string

func init() {
	// get config file from cli args
	flag.StringVar(&c, "c", "config/config.yaml", "config file")
	flag.Parse()

	contents, err := os.ReadFile(c)
	if err != nil {
		panic(err)
	}

	err = yaml.Unmarshal(contents, &config)
	if err != nil {
		panic(err)
	}
}

func main() {
	// Initialize server
	println("app name:", config.Name)
	println("app mode:", config.Mode)
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
