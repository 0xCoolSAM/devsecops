package com.devsecops;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

@Controller
public class NumericController {

    private final Logger logger = LoggerFactory.getLogger(getClass());

    private static final String baseURL = "http://node-service:5000/plusone";

    private RestTemplate restTemplate = new RestTemplate();

    // Landing Page Redirect
    @GetMapping("/")
    public String home() {
        return "redirect:/index.html";
    }

    // Compare endpoint
    @ResponseBody
    @GetMapping("/compare/{value}")
    public String compareToFifty(@PathVariable int value) {

        if (value > 50) {
            return "Greater than 50";
        }

        return "Smaller than or equal to 50";
    }

    // Call NodeJS microservice
    @ResponseBody
    @GetMapping("/increment/{value}")
    public int increment(@PathVariable int value) {

        ResponseEntity<String> responseEntity =
                restTemplate.getForEntity(baseURL + "/" + value, String.class);

        String response = responseEntity.getBody();

        logger.info("Value Received - {}", value);
        logger.info("Node Service Response - {}", response);

        return Integer.parseInt(response);
    }
}