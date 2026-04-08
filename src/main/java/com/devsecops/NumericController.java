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
    // private static final String baseURL = "http://localhost:5000/plusone";

    private RestTemplate restTemplate = new RestTemplate();

    // Landing Page
    @GetMapping("/")
    public String welcome() {
        return "index";
    }

    // Compare number endpoint
    @ResponseBody
    @GetMapping("/compare/{value}")
    public String compareToFifty(@PathVariable int value) {

        String message;

        if (value > 50) {
            message = "Greater than 50";
        } else {
            message = "Smaller than or equal to 50";
        }

        return message;
    }

    // Call node microservice
    @ResponseBody
    @GetMapping("/increment/{value}")
    public int increment(@PathVariable int value) {

        ResponseEntity<String> responseEntity =
                restTemplate.getForEntity(baseURL + "/" + value, String.class);

        String response = responseEntity.getBody();

        logger.info("Value Received in Request - {}", value);
        logger.info("Node Service Response - {}", response);

        return Integer.parseInt(response);
    }
}