package com.elgremio;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class ElGremioApplication {

    public static void main(String[] args) {
        SpringApplication.run(ElGremioApplication.class, args);
    }
}
